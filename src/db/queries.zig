const std = @import("std");
const core = @import("core.zig");
const c = @cImport({
    @cInclude("sqlite3.h");
});

const Database = core.Database;
const DbError = core.DbError;

pub const MAX_DEPTH: usize = 4;

pub fn getOrCreateProject(db: Database, path: []const u8) !i64 {
    const insert_stmt = try db.prepare("INSERT OR IGNORE INTO projects (path) VALUES (?);");
    defer Database.finalize(insert_stmt);
    try Database.bindText(insert_stmt, 1, path);
    if (!Database.stepDone(insert_stmt)) return DbError.StepFailed;

    const select_stmt = try db.prepare("SELECT id FROM projects WHERE path = ?;");
    defer Database.finalize(select_stmt);
    try Database.bindText(select_stmt, 1, path);

    if (Database.stepRow(select_stmt)) {
        return Database.columnInt(select_stmt, 0);
    }
    return DbError.StepFailed;
}

pub fn getProjectId(db: Database, path: []const u8) !i64 {
    const stmt = try db.prepare("SELECT id FROM projects WHERE path = ?;");
    defer Database.finalize(stmt);
    try Database.bindText(stmt, 1, path);

    if (Database.stepRow(stmt)) {
        return Database.columnInt(stmt, 0);
    }
    return DbError.NotFound;
}

pub fn getPlanId(db: Database, project_id: i64, name: []const u8) !i64 {
    const stmt = try db.prepare("SELECT id FROM plans WHERE project_id = ? AND name = ?;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, project_id);
    try Database.bindText(stmt, 2, name);

    if (Database.stepRow(stmt)) {
        return Database.columnInt(stmt, 0);
    }
    return DbError.NotFound;
}

pub fn resolveNodeId(db: Database, plan_id: i64, path_parts: []const []const u8) !?i64 {
    if (path_parts.len == 0) return null;

    var current_parent: ?i64 = null;

    for (path_parts) |part| {
        const stmt = if (current_parent == null)
            try db.prepare("SELECT id FROM nodes WHERE plan_id = ? AND parent_id IS NULL AND title = ?;")
        else
            try db.prepare("SELECT id FROM nodes WHERE plan_id = ? AND parent_id = ? AND title = ?;");
        defer Database.finalize(stmt);

        try Database.bindInt(stmt, 1, plan_id);
        if (current_parent) |pid| {
            try Database.bindInt(stmt, 2, pid);
            try Database.bindText(stmt, 3, part);
        } else {
            try Database.bindText(stmt, 2, part);
        }

        if (!Database.stepRow(stmt)) return DbError.InvalidPath;
        current_parent = Database.columnInt(stmt, 0);
    }

    return current_parent;
}

pub fn getNodeDepth(db: Database, node_id: i64) !usize {
    var depth: usize = 0;
    var current_id: ?i64 = node_id;

    while (current_id != null) {
        const stmt = try db.prepare("SELECT parent_id FROM nodes WHERE id = ?;");
        defer Database.finalize(stmt);
        try Database.bindInt(stmt, 1, current_id.?);

        if (!Database.stepRow(stmt)) break;

        if (Database.columnIsNull(stmt, 0)) {
            current_id = null;
        } else {
            current_id = Database.columnInt(stmt, 0);
        }
        depth += 1;
    }

    return depth;
}

pub fn getMaxPosition(db: Database, plan_id: i64, parent_id: ?i64) !i64 {
    const stmt = if (parent_id == null)
        try db.prepare("SELECT COALESCE(MAX(position), -1) FROM nodes WHERE plan_id = ? AND parent_id IS NULL;")
    else
        try db.prepare("SELECT COALESCE(MAX(position), -1) FROM nodes WHERE plan_id = ? AND parent_id = ?;");
    defer Database.finalize(stmt);

    try Database.bindInt(stmt, 1, plan_id);
    if (parent_id) |pid| {
        try Database.bindInt(stmt, 2, pid);
    }

    if (Database.stepRow(stmt)) {
        return Database.columnInt(stmt, 0);
    }
    return -1;
}

pub fn hasChildren(db: Database, node_id: i64) !bool {
    const stmt = try db.prepare("SELECT 1 FROM nodes WHERE parent_id = ? LIMIT 1;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, node_id);
    return Database.stepRow(stmt);
}

pub fn nextLocalId(db: Database, plan_id: i64) !i64 {
    // Get current value
    const get_stmt = try db.prepare("SELECT next_local_id FROM plans WHERE id = ?;");
    defer Database.finalize(get_stmt);
    try Database.bindInt(get_stmt, 1, plan_id);

    if (!Database.stepRow(get_stmt)) return DbError.NotFound;
    const local_id = Database.columnInt(get_stmt, 0);

    // Increment for next use
    const upd_stmt = try db.prepare("UPDATE plans SET next_local_id = next_local_id + 1 WHERE id = ?;");
    defer Database.finalize(upd_stmt);
    try Database.bindInt(upd_stmt, 1, plan_id);
    if (!Database.stepDone(upd_stmt)) return DbError.StepFailed;

    return local_id;
}

pub fn getNodeByLocalId(db: Database, plan_id: i64, local_id: i64) !?i64 {
    const stmt = try db.prepare("SELECT id FROM nodes WHERE plan_id = ? AND local_id = ?;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, plan_id);
    try Database.bindInt(stmt, 2, local_id);

    if (Database.stepRow(stmt)) {
        return Database.columnInt(stmt, 0);
    }
    return null;
}

pub fn markDoneRecursive(db: Database, node_id: i64, done: bool) !void {
    const update_stmt = try db.prepare("UPDATE nodes SET done = ?, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(update_stmt);
    try Database.bindInt(update_stmt, 1, if (done) 1 else 0);
    try Database.bindInt(update_stmt, 2, node_id);
    _ = Database.step(update_stmt);

    const cte_stmt = try db.prepare(
        \\WITH RECURSIVE descendants AS (
        \\    SELECT id FROM nodes WHERE parent_id = ?
        \\    UNION ALL
        \\    SELECT n.id FROM nodes n JOIN descendants d ON n.parent_id = d.id
        \\)
        \\UPDATE nodes SET done = ?, updated_at = datetime('now') WHERE id IN (SELECT id FROM descendants);
    );
    defer Database.finalize(cte_stmt);
    try Database.bindInt(cte_stmt, 1, node_id);
    try Database.bindInt(cte_stmt, 2, if (done) 1 else 0);
    _ = Database.step(cte_stmt);
}

pub fn propagateDoneUpward(db: Database, node_id: i64) !void {
    const parent_stmt = try db.prepare("SELECT parent_id FROM nodes WHERE id = ?;");
    defer Database.finalize(parent_stmt);
    try Database.bindInt(parent_stmt, 1, node_id);

    if (!Database.stepRow(parent_stmt)) return;
    if (Database.columnIsNull(parent_stmt, 0)) return;

    const parent_id = Database.columnInt(parent_stmt, 0);

    const check_stmt = try db.prepare("SELECT COUNT(*) FROM nodes WHERE parent_id = ? AND done = 0;");
    defer Database.finalize(check_stmt);
    try Database.bindInt(check_stmt, 1, parent_id);

    if (Database.stepRow(check_stmt)) {
        const undone_count = Database.columnInt(check_stmt, 0);
        if (undone_count == 0) {
            const update_stmt = try db.prepare("UPDATE nodes SET done = 1, updated_at = datetime('now') WHERE id = ?;");
            defer Database.finalize(update_stmt);
            try Database.bindInt(update_stmt, 1, parent_id);
            _ = Database.step(update_stmt);
            try propagateDoneUpward(db, parent_id);
        }
    }
}

pub fn propagateUndoneUpward(db: Database, node_id: i64) !void {
    const parent_stmt = try db.prepare("SELECT parent_id FROM nodes WHERE id = ?;");
    defer Database.finalize(parent_stmt);
    try Database.bindInt(parent_stmt, 1, node_id);

    if (!Database.stepRow(parent_stmt)) return;
    if (Database.columnIsNull(parent_stmt, 0)) return;

    const parent_id = Database.columnInt(parent_stmt, 0);

    const update_stmt = try db.prepare("UPDATE nodes SET done = 0, updated_at = datetime('now') WHERE id = ?;");
    defer Database.finalize(update_stmt);
    try Database.bindInt(update_stmt, 1, parent_id);
    _ = Database.step(update_stmt);

    try propagateUndoneUpward(db, parent_id);
}

pub fn countDescendants(db: Database, node_id: i64, total: *usize, done: *usize) !void {
    const stmt = try db.prepare("SELECT id, done FROM nodes WHERE parent_id = ?;");
    defer Database.finalize(stmt);
    try Database.bindInt(stmt, 1, node_id);

    while (Database.stepRow(stmt)) {
        const child_id = Database.columnInt(stmt, 0);
        const child_done = Database.columnInt(stmt, 1) != 0;

        total.* += 1;
        if (child_done) done.* += 1;

        try countDescendants(db, child_id, total, done);
    }
}
