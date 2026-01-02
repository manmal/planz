const std = @import("std");
const db_core = @import("../db/core.zig");
const queries = @import("../db/queries.zig");
const node_cmd = @import("node.zig");
const fmt = @import("../output/format.zig");

const Database = db_core.Database;
const DbError = db_core.DbError;
const Format = fmt.Format;

pub fn show(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: ?[]const u8, format: Format) !void {
    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    var root_id: ?i64 = null;
    if (identifier) |id| {
        root_id = try node_cmd.resolveNode(db, allocator, plan_id, id);
    }

    try fmt.printTree(db, allocator, plan_id, root_id, format, name);
}

pub fn progress(db: Database, _: std.mem.Allocator, project: []const u8, name: []const u8) !void {
    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    fmt.print("Progress for '{s}':\n\n", .{name});

    const stmt = try db.prepare("SELECT id, title, done FROM nodes WHERE plan_id = ? AND parent_id IS NULL ORDER BY position;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, plan_id);

    var total_all: usize = 0;
    var done_all: usize = 0;

    while (Database.stepRow(stmt)) {
        const node_id = Database.columnInt(stmt, 0);
        const title = Database.columnText(stmt, 1) orelse "";
        const node_done = Database.columnInt(stmt, 2) != 0;

        var total: usize = 1;
        var done: usize = if (node_done) 1 else 0;
        try queries.countDescendants(db, node_id, &total, &done);

        total_all += total;
        done_all += done;

        const bar_width: usize = 20;
        const filled = if (total > 0) (done * bar_width) / total else 0;
        var bar: [20]u8 = undefined;
        for (0..bar_width) |i| {
            bar[i] = if (i < filled) '#' else '-';
        }

        const pct = if (total > 0) (done * 100) / total else 0;
        fmt.print("  {s:<30} [{s}] {d}% ({d}/{d})\n", .{ title, &bar, pct, done, total });
    }

    fmt.puts("\n");
    const total_pct = if (total_all > 0) (done_all * 100) / total_all else 0;
    fmt.print("  Total: {d}% ({d}/{d})\n", .{ total_pct, done_all, total_all });
}
