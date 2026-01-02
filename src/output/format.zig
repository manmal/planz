const std = @import("std");
const posix = std.posix;
const db_core = @import("../db/core.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const Database = db_core.Database;

pub const Format = enum { text, json, xml, markdown };

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [16384]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = posix.write(posix.STDOUT_FILENO, msg) catch {};
}

pub fn eprint(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = posix.write(posix.STDERR_FILENO, msg) catch {};
}

pub fn puts(s: []const u8) void {
    _ = posix.write(posix.STDOUT_FILENO, s) catch {};
}

pub fn eputs(s: []const u8) void {
    _ = posix.write(posix.STDERR_FILENO, s) catch {};
}

pub fn printTree(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, format: Format, plan_name: []const u8) !void {
    switch (format) {
        .text => {
            print("# {s}\n\n", .{plan_name});
            try printTreeText(db, allocator, plan_id, parent_id, 0);
        },
        .json => try printTreeJson(db, allocator, plan_id, parent_id),
        .xml => try printTreeXml(db, allocator, plan_id, parent_id, plan_name),
        .markdown => try printTreeMarkdown(db, allocator, plan_id, parent_id, plan_name),
    }
}

fn printTreeText(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, indent: usize) !void {
    const stmt = if (parent_id == null)
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id IS NULL ORDER BY position;")
    else
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id = ? ORDER BY position;");
    defer Database.finalize(stmt);

    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| try Database.bindInt(stmt, 2, pid);

    while (Database.stepRow(stmt)) {
        const node_id = Database.columnInt(stmt, 0);
        const title = Database.columnText(stmt, 1) orelse "";
        const desc = Database.columnText(stmt, 2) orelse "";
        const done = Database.columnInt(stmt, 3) != 0;
        const local_id = Database.columnInt(stmt, 4);

        var i: usize = 0;
        while (i < indent) : (i += 1) puts("  ");

        if (done) {
            print("- [x] {s} [{d}]\n", .{ title, local_id });
        } else {
            print("- [ ] {s} [{d}]\n", .{ title, local_id });
        }

        if (desc.len > 0) {
            i = 0;
            while (i < indent + 1) : (i += 1) puts("  ");
            print("{s}\n", .{desc});
        }

        try printTreeText(db, allocator, plan_id, node_id, indent + 1);
    }
}

fn printTreeJson(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(allocator);

    try buildJsonTree(db, allocator, plan_id, parent_id, &output);
    puts(output.items);
    puts("\n");
}

fn buildJsonTree(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, output: *std.ArrayListUnmanaged(u8)) !void {
    const stmt = if (parent_id == null)
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id IS NULL ORDER BY position;")
    else
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id = ? ORDER BY position;");
    defer Database.finalize(stmt);

    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| try Database.bindInt(stmt, 2, pid);

    try output.appendSlice(allocator, "[");
    var first = true;

    while (Database.stepRow(stmt)) {
        if (!first) try output.appendSlice(allocator, ",");
        first = false;

        const node_id = Database.columnInt(stmt, 0);
        const title = Database.columnText(stmt, 1) orelse "";
        const desc = Database.columnText(stmt, 2) orelse "";
        const done = Database.columnInt(stmt, 3) != 0;
        const local_id = Database.columnInt(stmt, 4);

        var id_buf: [32]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{local_id}) catch "0";

        try output.appendSlice(allocator, "{\"id\":");
        try output.appendSlice(allocator, id_str);
        try output.appendSlice(allocator, ",\"title\":\"");
        try appendEscaped(allocator, output, title, .json);
        try output.appendSlice(allocator, "\",\"done\":");
        try output.appendSlice(allocator, if (done) "true" else "false");

        if (desc.len > 0) {
            try output.appendSlice(allocator, ",\"description\":\"");
            try appendEscaped(allocator, output, desc, .json);
            try output.appendSlice(allocator, "\"");
        }

        try output.appendSlice(allocator, ",\"children\":");
        try buildJsonTree(db, allocator, plan_id, node_id, output);
        try output.appendSlice(allocator, "}");
    }

    try output.appendSlice(allocator, "]");
}

fn printTreeXml(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, plan_name: []const u8) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<plan name=\"");
    try appendEscaped(allocator, &output, plan_name, .xml);
    try output.appendSlice(allocator, "\">\n");
    try buildXmlTree(db, allocator, plan_id, parent_id, &output, 1);
    try output.appendSlice(allocator, "</plan>\n");

    puts(output.items);
}

fn buildXmlTree(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, output: *std.ArrayListUnmanaged(u8), depth: usize) !void {
    const stmt = if (parent_id == null)
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id IS NULL ORDER BY position;")
    else
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id = ? ORDER BY position;");
    defer Database.finalize(stmt);

    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| try Database.bindInt(stmt, 2, pid);

    while (Database.stepRow(stmt)) {
        const node_id = Database.columnInt(stmt, 0);
        const title = Database.columnText(stmt, 1) orelse "";
        const desc = Database.columnText(stmt, 2) orelse "";
        const done = Database.columnInt(stmt, 3) != 0;
        const local_id = Database.columnInt(stmt, 4);

        // Indent
        var i: usize = 0;
        while (i < depth) : (i += 1) try output.appendSlice(allocator, "  ");

        var id_buf: [32]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{local_id}) catch "0";

        try output.appendSlice(allocator, "<node id=\"");
        try output.appendSlice(allocator, id_str);
        try output.appendSlice(allocator, "\" title=\"");
        try appendEscaped(allocator, output, title, .xml);
        try output.appendSlice(allocator, "\" done=\"");
        try output.appendSlice(allocator, if (done) "true" else "false");
        try output.appendSlice(allocator, "\"");

        // Check for children or description
        const has_desc = desc.len > 0;
        const has_kids = try hasChildrenForXml(db, node_id);

        if (!has_desc and !has_kids) {
            try output.appendSlice(allocator, " />\n");
        } else {
            try output.appendSlice(allocator, ">\n");

            if (has_desc) {
                i = 0;
                while (i < depth + 1) : (i += 1) try output.appendSlice(allocator, "  ");
                try output.appendSlice(allocator, "<description>");
                try appendEscaped(allocator, output, desc, .xml);
                try output.appendSlice(allocator, "</description>\n");
            }

            try buildXmlTree(db, allocator, plan_id, node_id, output, depth + 1);

            i = 0;
            while (i < depth) : (i += 1) try output.appendSlice(allocator, "  ");
            try output.appendSlice(allocator, "</node>\n");
        }
    }
}

fn hasChildrenForXml(db: Database, node_id: i64) !bool {
    const stmt = try db.prepare("SELECT 1 FROM nodes WHERE parent_id = ? LIMIT 1;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, node_id);
    return Database.stepRow(stmt);
}

fn printTreeMarkdown(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, plan_name: []const u8) !void {
    var output: std.ArrayListUnmanaged(u8) = .empty;
    defer output.deinit(allocator);

    try output.appendSlice(allocator, "# ");
    try output.appendSlice(allocator, plan_name);
    try output.appendSlice(allocator, "\n\n");
    try buildMarkdownTree(db, allocator, plan_id, parent_id, &output, 0);

    puts(output.items);
}

fn buildMarkdownTree(db: Database, allocator: std.mem.Allocator, plan_id: i64, parent_id: ?i64, output: *std.ArrayListUnmanaged(u8), depth: usize) !void {
    const stmt = if (parent_id == null)
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id IS NULL ORDER BY position;")
    else
        try db.prepare("SELECT id, title, description, done, local_id FROM nodes WHERE plan_id = ? AND parent_id = ? ORDER BY position;");
    defer Database.finalize(stmt);

    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| try Database.bindInt(stmt, 2, pid);

    while (Database.stepRow(stmt)) {
        const node_id = Database.columnInt(stmt, 0);
        const title = Database.columnText(stmt, 1) orelse "";
        const desc = Database.columnText(stmt, 2) orelse "";
        const done = Database.columnInt(stmt, 3) != 0;
        const local_id = Database.columnInt(stmt, 4);

        var id_buf: [32]u8 = undefined;
        const id_str = std.fmt.bufPrint(&id_buf, "{d}", .{local_id}) catch "0";

        // Indent
        var i: usize = 0;
        while (i < depth) : (i += 1) try output.appendSlice(allocator, "  ");

        // Checkbox with id suffix
        if (done) {
            try output.appendSlice(allocator, "- [x] ");
        } else {
            try output.appendSlice(allocator, "- [ ] ");
        }
        try output.appendSlice(allocator, title);
        try output.appendSlice(allocator, " [");
        try output.appendSlice(allocator, id_str);
        try output.appendSlice(allocator, "]\n");

        // Description as indented paragraph
        if (desc.len > 0) {
            try output.appendSlice(allocator, "\n");
            i = 0;
            while (i < depth + 1) : (i += 1) try output.appendSlice(allocator, "  ");
            try output.appendSlice(allocator, desc);
            try output.appendSlice(allocator, "\n\n");
        }

        try buildMarkdownTree(db, allocator, plan_id, node_id, output, depth + 1);
    }
}

const EscapeMode = enum { json, xml };

fn appendEscaped(allocator: std.mem.Allocator, output: *std.ArrayListUnmanaged(u8), s: []const u8, mode: EscapeMode) !void {
    for (s) |ch| {
        switch (mode) {
            .json => switch (ch) {
                '"' => try output.appendSlice(allocator, "\\\""),
                '\\' => try output.appendSlice(allocator, "\\\\"),
                '\n' => try output.appendSlice(allocator, "\\n"),
                '\r' => try output.appendSlice(allocator, "\\r"),
                '\t' => try output.appendSlice(allocator, "\\t"),
                else => try output.append(allocator, ch),
            },
            .xml => switch (ch) {
                '<' => try output.appendSlice(allocator, "&lt;"),
                '>' => try output.appendSlice(allocator, "&gt;"),
                '&' => try output.appendSlice(allocator, "&amp;"),
                '"' => try output.appendSlice(allocator, "&quot;"),
                '\'' => try output.appendSlice(allocator, "&apos;"),
                else => try output.append(allocator, ch),
            },
        }
    }
}
