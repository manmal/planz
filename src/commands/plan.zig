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

pub fn create(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = try queries.getOrCreateProject(db, project);

    const stmt = try db.prepare("INSERT INTO plans (project_id, name) VALUES (?, ?);");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, project_id);
    try Database.bindText(stmt, 2, name);

    const rc = Database.step(stmt);
    if (rc == c.SQLITE_CONSTRAINT) return DbError.AlreadyExists;
    if (rc != c.SQLITE_DONE) return DbError.StepFailed;

    try tx.commit();
    format.print("Created plan '{s}'\n", .{name});
}

pub fn delete(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;

    const stmt = try db.prepare("DELETE FROM plans WHERE project_id = ? AND name = ?;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, project_id);
    try Database.bindText(stmt, 2, name);

    if (!Database.stepDone(stmt)) return DbError.StepFailed;
    if (db.changes() == 0) return DbError.NotFound;

    try tx.commit();
    format.print("Deleted plan '{s}'\n", .{name});
}

pub fn list(db: Database, project: []const u8) !void {
    const project_id = queries.getProjectId(db, project) catch {
        format.print("No plans found for project: {s}\n", .{project});
        return;
    };

    const stmt = try db.prepare(
        \\SELECT p.name, p.summary, p.created_at, p.updated_at,
        \\       (SELECT COUNT(*) FROM nodes WHERE plan_id = p.id) as node_count
        \\FROM plans p WHERE p.project_id = ? ORDER BY p.updated_at DESC;
    );
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, project_id);

    format.print("Plans for: {s}\n\n", .{project});
    format.print("{s:<20} {s:<8} {s:<20} {s:<20} {s}\n", .{ "NAME", "NODES", "CREATED", "UPDATED", "SUMMARY" });
    format.puts("-" ** 100 ++ "\n");

    while (Database.stepRow(stmt)) {
        const pname = Database.columnText(stmt, 0) orelse "";
        const summary = Database.columnText(stmt, 1) orelse "";
        const created = Database.columnText(stmt, 2) orelse "";
        const updated = Database.columnText(stmt, 3) orelse "";
        const nodes = Database.columnInt(stmt, 4);

        const display_summary = if (summary.len > 30) summary[0..30] else summary;
        format.print("{s:<20} {d:<8} {s:<20} {s:<20} {s}\n", .{ pname, nodes, created, updated, display_summary });
    }
}

pub fn projects(db: Database) !void {
    const stmt = try db.prepare(
        \\SELECT p.path, COUNT(pl.id), MAX(pl.updated_at)
        \\FROM projects p LEFT JOIN plans pl ON p.id = pl.project_id
        \\GROUP BY p.id ORDER BY MAX(pl.updated_at) DESC;
    );
    defer Database.finalize(stmt);

    format.print("{s:<50} {s:<8} {s}\n", .{ "PROJECT", "PLANS", "LAST UPDATED" });
    format.puts("-" ** 80 ++ "\n");

    while (Database.stepRow(stmt)) {
        const path = Database.columnText(stmt, 0) orelse "";
        const count = Database.columnInt(stmt, 1);
        const updated = Database.columnText(stmt, 2) orelse "never";

        format.print("{s:<50} {d:<8} {s}\n", .{ path, count, updated });
    }
}

pub fn deleteProject(db: Database, allocator: std.mem.Allocator, project: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const stmt = try db.prepare("DELETE FROM projects WHERE path = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, project);

    if (!Database.stepDone(stmt)) return DbError.StepFailed;
    const changes = db.changes();

    try tx.commit();

    if (changes == 0) {
        format.print("No project found: {s}\n", .{project});
    } else {
        format.print("Deleted project and all plans: {s}\n", .{project});
    }
}

pub fn renamePlan(db: Database, allocator: std.mem.Allocator, project: []const u8, old_name: []const u8, new_name: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;

    const stmt = try db.prepare("UPDATE plans SET name = ?, updated_at = datetime('now') WHERE project_id = ? AND name = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, new_name);
    try Database.bindInt(stmt, 2, project_id);
    try Database.bindText(stmt, 3, old_name);

    const rc = Database.step(stmt);
    if (rc == c.SQLITE_CONSTRAINT) return DbError.AlreadyExists;
    if (rc != c.SQLITE_DONE) return DbError.StepFailed;
    if (db.changes() == 0) return DbError.NotFound;

    try tx.commit();
    format.print("Renamed plan '{s}' to '{s}'\n", .{ old_name, new_name });
}

pub fn summarize(db: Database, allocator: std.mem.Allocator, project: []const u8, name: []const u8, summary: []const u8) !void {
    var tx = try WriteTx.begin(db, allocator);
    defer tx.deinit();

    const project_id = queries.getProjectId(db, project) catch return DbError.NotFound;

    const stmt = try db.prepare("UPDATE plans SET summary = ?, updated_at = datetime('now') WHERE project_id = ? AND name = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, summary);
    try Database.bindInt(stmt, 2, project_id);
    try Database.bindText(stmt, 3, name);

    if (!Database.stepDone(stmt)) return DbError.StepFailed;
    if (db.changes() == 0) return DbError.NotFound;

    try tx.commit();
    format.print("Updated summary for '{s}'\n", .{name});
}
