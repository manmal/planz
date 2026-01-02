const std = @import("std");
const db_core = @import("../db/core.zig");
const queries = @import("../db/queries.zig");
const format = @import("../output/format.zig");
const node = @import("node.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const Database = db_core.Database;
const DbError = db_core.DbError;
const WriteTx = db_core.WriteTx;
const MAX_DEPTH = queries.MAX_DEPTH;

pub fn refine(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, identifier: []const u8, children: []const []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;
    const plan_id = queries.getPlanId(db, project_id, name) catch return DbError.NotFound;

    const node_id = (try node.resolveNode(db, allocator, plan_id, identifier)) orelse return DbError.InvalidPath;

    // Check node is a leaf (no children)
    if (try queries.hasChildren(db, node_id)) return DbError.HasChildren;

    // Check depth allows refinement
    const current_depth = try queries.getNodeDepth(db, node_id);
    if (current_depth >= MAX_DEPTH) return DbError.MaxDepthExceeded;

    // Add each child path relative to the target node
    var added: usize = 0;
    for (children) |child_path| {
        const child_parts = try node.parsePath(allocator, child_path);
        defer allocator.free(child_parts);

        if (child_parts.len == 0) continue;

        // Check total depth won't exceed max
        if (current_depth + child_parts.len > MAX_DEPTH) continue;

        // Resolve or create parent chain
        var parent_id: i64 = node_id;
        for (child_parts[0 .. child_parts.len - 1]) |part| {
            // Try to find existing node
            const find_stmt = try db.prepare("SELECT id FROM nodes WHERE plan_id = ? AND parent_id = ? AND title = ?;");
            defer Database.finalize(find_stmt);
            try Database.bindInt(find_stmt, 1, plan_id);
            try Database.bindInt(find_stmt, 2, parent_id);
            try Database.bindText(find_stmt, 3, part);

            if (Database.stepRow(find_stmt)) {
                parent_id = Database.columnInt(find_stmt, 0);
            } else {
                // Create intermediate node
                const pos = try queries.getMaxPosition(db, plan_id, parent_id) + 1;
                const lid = try queries.nextLocalId(db, plan_id);
                const ins_stmt = try db.prepare("INSERT INTO nodes (plan_id, parent_id, title, position, local_id) VALUES (?, ?, ?, ?, ?);");
                defer Database.finalize(ins_stmt);
                try Database.bindInt(ins_stmt, 1, plan_id);
                try Database.bindInt(ins_stmt, 2, parent_id);
                try Database.bindText(ins_stmt, 3, part);
                try Database.bindInt(ins_stmt, 4, pos);
                try Database.bindInt(ins_stmt, 5, lid);

                const rc = Database.step(ins_stmt);
                if (rc == c.SQLITE_CONSTRAINT) continue; // Skip duplicates
                if (rc != c.SQLITE_DONE) continue;

                parent_id = db.lastInsertRowId();
            }
        }

        // Add the leaf node
        const leaf_title = child_parts[child_parts.len - 1];
        if (!node.isValidTitle(leaf_title)) continue;

        const pos = try queries.getMaxPosition(db, plan_id, parent_id) + 1;
        const lid = try queries.nextLocalId(db, plan_id);
        const stmt = try db.prepare("INSERT INTO nodes (plan_id, parent_id, title, position, local_id) VALUES (?, ?, ?, ?, ?);");
        defer Database.finalize(stmt);
        try Database.bindInt(stmt, 1, plan_id);
        try Database.bindInt(stmt, 2, parent_id);
        try Database.bindText(stmt, 3, leaf_title);
        try Database.bindInt(stmt, 4, pos);
        try Database.bindInt(stmt, 5, lid);

        const rc = Database.step(stmt);
        if (rc == c.SQLITE_CONSTRAINT) continue; // Skip duplicates
        if (rc != c.SQLITE_DONE) continue;
        added += 1;
    }

    try tx.commit();
    format.print("Refined '{s}' with {d} node(s)\n", .{ identifier, added });
}
