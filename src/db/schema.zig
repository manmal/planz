const std = @import("std");
const core = @import("core.zig");

const Database = core.Database;
const DbError = core.DbError;
const WriteLock = core.WriteLock;

pub const SCHEMA_VERSION: i32 = 4;

pub fn ensureSchema(db: Database, allocator: std.mem.Allocator) !void {
    const lock = try WriteLock.acquire(allocator);
    defer lock.release();

    const version = getUserVersion(db);
    if (version >= SCHEMA_VERSION) return;

    // Version 1: projects and plans tables
    if (version < 1) {
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS projects (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    path TEXT NOT NULL UNIQUE,
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    updated_at TEXT DEFAULT (datetime('now'))
            \\);
        );
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS plans (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            \\    name TEXT NOT NULL,
            \\    summary TEXT NOT NULL DEFAULT '',
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    updated_at TEXT DEFAULT (datetime('now')),
            \\    UNIQUE(project_id, name)
            \\);
        );
        try db.exec("CREATE INDEX IF NOT EXISTS idx_plans_project ON plans(project_id);");
    }

    // Version 2: nodes table for tree structure
    if (version < 2) {
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS nodes (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    plan_id INTEGER NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
            \\    parent_id INTEGER REFERENCES nodes(id) ON DELETE CASCADE,
            \\    title TEXT NOT NULL,
            \\    description TEXT NOT NULL DEFAULT '',
            \\    done INTEGER NOT NULL DEFAULT 0,
            \\    position INTEGER NOT NULL DEFAULT 0,
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    updated_at TEXT DEFAULT (datetime('now'))
            \\);
        );
        try db.exec("CREATE INDEX IF NOT EXISTS idx_nodes_plan ON nodes(plan_id);");
        try db.exec("CREATE INDEX IF NOT EXISTS idx_nodes_parent ON nodes(parent_id);");
        try db.exec("CREATE INDEX IF NOT EXISTS idx_nodes_plan_parent ON nodes(plan_id, parent_id);");
        try db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_root_title ON nodes(plan_id, title) WHERE parent_id IS NULL;");
        try db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_child_title ON nodes(plan_id, parent_id, title) WHERE parent_id IS NOT NULL;");
    }

    // Version 3: drop legacy content column
    if (version < 3) {
        try db.exec(
            \\CREATE TABLE IF NOT EXISTS plans_new (
            \\    id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\    project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
            \\    name TEXT NOT NULL,
            \\    summary TEXT NOT NULL DEFAULT '',
            \\    created_at TEXT DEFAULT (datetime('now')),
            \\    updated_at TEXT DEFAULT (datetime('now')),
            \\    UNIQUE(project_id, name)
            \\);
        );
        try db.exec("INSERT OR IGNORE INTO plans_new (id, project_id, name, summary, created_at, updated_at) SELECT id, project_id, name, summary, created_at, updated_at FROM plans;");
        try db.exec("DROP TABLE IF EXISTS plans;");
        try db.exec("ALTER TABLE plans_new RENAME TO plans;");
        try db.exec("CREATE INDEX IF NOT EXISTS idx_plans_project ON plans(project_id);");
    }

    // Version 4: add local_id (per-plan auto-increment for stable node IDs)
    if (version < 4) {
        try db.exec("ALTER TABLE nodes ADD COLUMN local_id INTEGER;");
        try db.exec(
            \\UPDATE nodes SET local_id = (
            \\    SELECT COUNT(*) FROM nodes n2 
            \\    WHERE n2.plan_id = nodes.plan_id AND n2.id <= nodes.id
            \\);
        );
        try db.exec("CREATE UNIQUE INDEX IF NOT EXISTS idx_nodes_local ON nodes(plan_id, local_id);");
        try db.exec("ALTER TABLE plans ADD COLUMN next_local_id INTEGER DEFAULT 1;");
        try db.exec(
            \\UPDATE plans SET next_local_id = COALESCE(
            \\    (SELECT MAX(local_id) + 1 FROM nodes WHERE plan_id = plans.id), 1
            \\);
        );
    }

    try setUserVersion(db, SCHEMA_VERSION);
}

fn getUserVersion(db: Database) i32 {
    const stmt = db.prepare("PRAGMA user_version;") catch return 0;
    defer Database.finalize(stmt);
    if (Database.stepRow(stmt)) {
        return @intCast(Database.columnInt(stmt, 0));
    }
    return 0;
}

fn setUserVersion(db: Database, version: i32) !void {
    var buf: [64]u8 = undefined;
    const sql = std.fmt.bufPrintZ(&buf, "PRAGMA user_version = {d};", .{version}) catch return DbError.QueryFailed;
    try db.exec(sql);
}
