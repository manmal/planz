const std = @import("std");
const db_core = @import("../db/core.zig");
const queries = @import("../db/queries.zig");
const format = @import("../output/format.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const Database = db_core.Database;
const DbError = db_core.DbError;
const WriteTx = db_core.WriteTx;

pub const MAX_DEPTH = queries.MAX_DEPTH;

pub fn parsePath(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
    if (path.len == 0) return &[_][]const u8{};

    var parts: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer parts.deinit(allocator);

    var iter = std.mem.splitScalar(u8, path, '/');
    while (iter.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " \t");
        if (trimmed.len > 0) try parts.append(allocator, trimmed);
    }

    if (parts.items.len > MAX_DEPTH) return DbError.MaxDepthExceeded;
    return try parts.toOwnedSlice(allocator);
}

pub fn isValidTitle(title: []const u8) bool {
    if (title.len == 0) return false;
    for (title) |ch| if (ch == '/') return false;
    return true;
}

fn validateTitle(title: []const u8) !void {
    if (!isValidTitle(title)) return DbError.InvalidTitle;
}

pub fn add(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, path: []const u8, desc: ?[]const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const path_parts = try parsePath(allocator, path);
    defer allocator.free(path_parts);

    if (path_parts.len == 0) return DbError.InvalidPath;

    const new_title = path_parts[path_parts.len - 1];
    try validateTitle(new_title);

    var parent_id: ?i64 = null;
    if (path_parts.len > 1) {
        parent_id = try queries.resolveNodeId(db, plan_id, path_parts[0 .. path_parts.len - 1]);
        if (parent_id) |pid| {
            const depth = try queries.getNodeDepth(db, pid);
            if (depth >= MAX_DEPTH) return DbError.MaxDepthExceeded;
        }
    }

    const pos = try queries.getMaxPosition(db, plan_id, parent_id) + 1;
    const local_id = try queries.nextLocalId(db, plan_id);

    const stmt = try db.prepare(
        \\INSERT INTO nodes (plan_id, parent_id, title, description, position, local_id)
        \\VALUES (?, ?, ?, ?, ?, ?);
    );
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| {
        try Database.bindInt(stmt, 2, pid);
    } else {
        try Database.bindNull(stmt, 2);
    }
    try Database.bindText(stmt, 3, new_title);
    try Database.bindText(stmt, 4, desc orelse "");
    try Database.bindInt(stmt, 5, pos);
    try Database.bindInt(stmt, 6, local_id);

    const rc = Database.step(stmt);
    if (rc == c.SQLITE_CONSTRAINT) return DbError.DuplicateTitle;
    if (rc != c.SQLITE_DONE) return DbError.StepFailed;

    try tx.commit();
    format.print("Added '{s}'\n", .{path});
}

pub fn remove(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: []const u8, force: bool) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const node_id = (try resolveNode(db, allocator, plan_id, identifier)) orelse return DbError.InvalidPath;

    if (!force and try queries.hasChildren(db, node_id)) return DbError.HasChildren;

    const stmt = try db.prepare("DELETE FROM nodes WHERE id = ?;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, node_id);

    if (!Database.stepDone(stmt)) return DbError.StepFailed;

    try tx.commit();
    format.print("Removed '{s}'\n", .{identifier});
}

pub fn rename(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: []const u8, new_title: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    try validateTitle(new_title);

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const node_id = (try resolveNode(db, allocator, plan_id, identifier)) orelse return DbError.InvalidPath;

    const stmt = try db.prepare("UPDATE nodes SET title = ?, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, new_title);
    try Database.bindInt(stmt, 2, node_id);

    const rc = Database.step(stmt);
    if (rc == c.SQLITE_CONSTRAINT) return DbError.DuplicateTitle;
    if (rc != c.SQLITE_DONE) return DbError.StepFailed;

    try tx.commit();
    format.print("Renamed to '{s}'\n", .{new_title});
}

pub fn describe(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: []const u8, desc: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const node_id = (try resolveNode(db, allocator, plan_id, identifier)) orelse return DbError.InvalidPath;

    const stmt = try db.prepare("UPDATE nodes SET description = ?, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, desc);
    try Database.bindInt(stmt, 2, node_id);

    if (!Database.stepDone(stmt)) return DbError.StepFailed;

    try tx.commit();
    format.print("Updated description for '{s}'\n", .{identifier});
}

pub fn done(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifiers: []const []const u8, mark_done: bool) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    for (identifiers) |identifier| {
        const node_id = (try resolveNode(db, allocator, plan_id, identifier)) orelse continue;

        if (mark_done) {
            try queries.markDoneRecursive(db, node_id, true);
            try queries.propagateDoneUpward(db, node_id);
        } else {
            const update_stmt = try db.prepare("UPDATE nodes SET done = 0, updated_at = datetime('now') WHERE id = ?;");
            defer Database.finalize(update_stmt);
            try Database.bindInt(update_stmt, 1, node_id);
            _ = Database.step(update_stmt);
            try queries.propagateUndoneUpward(db, node_id);
        }
    }

    try tx.commit();
    const action = if (mark_done) "done" else "undone";
    format.print("Marked {d} item(s) as {s}\n", .{ identifiers.len, action });
}

pub fn move(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: []const u8, to_parent: ?[]const u8, after_sibling: ?[]const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const node_id = (try resolveNode(db, allocator, plan_id, identifier)) orelse return DbError.InvalidPath;

    if (to_parent) |tp| {
        try moveToParent(db, allocator, plan_id, node_id, tp);
    } else if (after_sibling) |sibling| {
        try moveAfterSibling(db, plan_id, node_id, sibling);
    }

    try tx.commit();
    format.print("Moved '{s}'\n", .{identifier});
}

fn moveToParent(db: Database, allocator: std.mem.Allocator, plan_id: i64, node_id: i64, to_parent_id: []const u8) !void {
    var new_parent_id: ?i64 = null;
    if (to_parent_id.len > 0) {
        new_parent_id = try resolveNode(db, allocator, plan_id, to_parent_id);
    }

    if (new_parent_id) |pid| {
        const depth = try queries.getNodeDepth(db, pid);
        if (depth >= MAX_DEPTH) return DbError.MaxDepthExceeded;
    }

    const pos = try queries.getMaxPosition(db, plan_id, new_parent_id) + 1;

    const stmt = try db.prepare("UPDATE nodes SET parent_id = ?, position = ?, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(stmt);
    if (new_parent_id) |pid| {
        try Database.bindInt(stmt, 1, pid);
    } else {
        try Database.bindNull(stmt, 1);
    }
    try Database.bindInt(stmt, 2, pos);
    try Database.bindInt(stmt, 3, node_id);

    const rc = Database.step(stmt);
    if (rc == c.SQLITE_CONSTRAINT) return DbError.DuplicateTitle;
    if (rc != c.SQLITE_DONE) return DbError.StepFailed;
}

/// Resolve node by path or #local_id (e.g., "#5" or "Phase 1/Task A")
pub fn resolveNode(db: Database, allocator: std.mem.Allocator, plan_id: i64, identifier: []const u8) !?i64 {
    // Check for #id syntax
    if (identifier.len > 1 and identifier[0] == '#') {
        const id_str = identifier[1..];
        const local_id = std.fmt.parseInt(i64, id_str, 10) catch return DbError.InvalidPath;
        return queries.getNodeByLocalId(db, plan_id, local_id);
    }

    // Otherwise resolve as path
    const path_parts = try parsePath(allocator, identifier);
    defer allocator.free(path_parts);
    return queries.resolveNodeId(db, plan_id, path_parts);
}

fn moveAfterSibling(db: Database, plan_id: i64, node_id: i64, sibling: []const u8) !void {
    // Get current parent
    const parent_stmt = try db.prepare("SELECT parent_id FROM nodes WHERE id = ?;");
    defer Database.finalize(parent_stmt);
    try Database.bindInt(parent_stmt, 1, node_id);

    if (!Database.stepRow(parent_stmt)) return DbError.NotFound;

    var parent_id: ?i64 = null;
    if (!Database.columnIsNull(parent_stmt, 0)) {
        parent_id = Database.columnInt(parent_stmt, 0);
    }

    // Find sibling position
    const sibling_stmt = if (parent_id == null)
        try db.prepare("SELECT position FROM nodes WHERE plan_id = ? AND parent_id IS NULL AND title = ?;")
    else
        try db.prepare("SELECT position FROM nodes WHERE plan_id = ? AND parent_id = ? AND title = ?;");
    defer Database.finalize(sibling_stmt);

    try Database.bindInt(sibling_stmt, 1, plan_id);
    if (parent_id) |pid| {
        try Database.bindInt(sibling_stmt, 2, pid);
        try Database.bindText(sibling_stmt, 3, sibling);
    } else {
        try Database.bindText(sibling_stmt, 2, sibling);
    }

    if (!Database.stepRow(sibling_stmt)) return DbError.NotFound;
    const sibling_pos = Database.columnInt(sibling_stmt, 0);

    // Shift others
    const shift_stmt = if (parent_id == null)
        try db.prepare("UPDATE nodes SET position = position + 1 WHERE plan_id = ? AND parent_id IS NULL AND position > ? AND id != ?;")
    else
        try db.prepare("UPDATE nodes SET position = position + 1 WHERE plan_id = ? AND parent_id = ? AND position > ? AND id != ?;");
    defer Database.finalize(shift_stmt);

    try Database.bindInt(shift_stmt, 1, plan_id);
    if (parent_id) |pid| {
        try Database.bindInt(shift_stmt, 2, pid);
        try Database.bindInt(shift_stmt, 3, sibling_pos);
        try Database.bindInt(shift_stmt, 4, node_id);
    } else {
        try Database.bindInt(shift_stmt, 2, sibling_pos);
        try Database.bindInt(shift_stmt, 3, node_id);
    }
    _ = Database.step(shift_stmt);

    const update_stmt = try db.prepare("UPDATE nodes SET position = ?, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(update_stmt);
    try Database.bindInt(update_stmt, 1, sibling_pos + 1);
    try Database.bindInt(update_stmt, 2, node_id);
    _ = Database.step(update_stmt);
}
