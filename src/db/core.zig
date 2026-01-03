const std = @import("std");
const posix = std.posix;
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const DB_DIR = "/.local/share/planz";
pub const DB_NAME = "/plans.db";
pub const LOCK_NAME = "/plans.db.lock";
const schema = @import("schema.zig");
pub const SCHEMA_VERSION = schema.SCHEMA_VERSION;

pub const DbError = error{
    OpenFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    QueryFailed,
    NotFound,
    AlreadyExists,
    TransactionFailed,
    LockFailed,
    DuplicateTitle,
    MaxDepthExceeded,
    InvalidPath,
    HasChildren,
    InvalidTitle,
};

pub const WriteLock = struct {
    fd: posix.fd_t,

    pub fn acquire(allocator: std.mem.Allocator) !WriteLock {
        const home = posix.getenv("HOME") orelse return DbError.LockFailed;
        const lock_path_slice = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ home, DB_DIR, LOCK_NAME });
        defer allocator.free(lock_path_slice);
        const lock_path = try allocator.dupeZ(u8, lock_path_slice);
        defer allocator.free(lock_path);

        const fd = posix.open(lock_path, .{ .ACCMODE = .RDWR, .CREAT = true }, 0o644) catch {
            return DbError.LockFailed;
        };

        _ = posix.flock(fd, posix.LOCK.EX) catch {
            posix.close(fd);
            return DbError.LockFailed;
        };

        return WriteLock{ .fd = fd };
    }

    pub fn release(self: WriteLock) void {
        _ = posix.flock(self.fd, posix.LOCK.UN) catch {};
        posix.close(self.fd);
    }
};

pub const WriteTx = struct {
    db: Database,
    lock: WriteLock,
    committed: bool = false,

    pub fn begin(db: Database, allocator: std.mem.Allocator) !WriteTx {
        const lock = try WriteLock.acquire(allocator);
        errdefer lock.release();

        const rc = c.sqlite3_exec(db.db, "BEGIN IMMEDIATE;", null, null, null);
        if (rc != c.SQLITE_OK) {
            return DbError.TransactionFailed;
        }

        return WriteTx{ .db = db, .lock = lock };
    }

    pub fn commit(self: *WriteTx) !void {
        const rc = c.sqlite3_exec(self.db.db, "COMMIT;", null, null, null);
        if (rc != c.SQLITE_OK) {
            return DbError.TransactionFailed;
        }
        self.committed = true;
    }

    pub fn deinit(self: *WriteTx) void {
        if (!self.committed) {
            _ = c.sqlite3_exec(self.db.db, "ROLLBACK;", null, null, null);
        }
        self.lock.release();
    }
};

pub const Database = struct {
    db: *c.sqlite3,

    pub fn open(allocator: std.mem.Allocator, needs_write: bool) !Database {
        const home = posix.getenv("HOME") orelse return DbError.OpenFailed;
        const db_path_slice = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ home, DB_DIR, DB_NAME });
        defer allocator.free(db_path_slice);
        const db_path = try allocator.dupeZ(u8, db_path_slice);
        defer allocator.free(db_path);

        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(db_path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            if (db) |d| _ = c.sqlite3_close(d);
            return DbError.OpenFailed;
        }

        const self = Database{ .db = db.? };

        try self.exec("PRAGMA journal_mode = WAL;");
        try self.exec("PRAGMA synchronous = NORMAL;");
        try self.exec("PRAGMA foreign_keys = ON;");

        if (needs_write) {
            try self.ensureSchema(allocator);
        }

        return self;
    }

    pub fn close(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }

    pub fn exec(self: Database, sql: [*:0]const u8) !void {
        const rc = c.sqlite3_exec(self.db, sql, null, null, null);
        if (rc != c.SQLITE_OK) {
            return DbError.QueryFailed;
        }
    }

    pub fn prepare(self: Database, sql: [*:0]const u8) !*c.sqlite3_stmt {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            return DbError.PrepareFailed;
        }
        return stmt.?;
    }

    pub fn changes(self: Database) i32 {
        return c.sqlite3_changes(self.db);
    }

    pub fn lastInsertRowId(self: Database) i64 {
        return c.sqlite3_last_insert_rowid(self.db);
    }

    pub fn bindText(stmt: *c.sqlite3_stmt, idx: c_int, text: []const u8) !void {
        const rc = c.sqlite3_bind_text(stmt, idx, text.ptr, @intCast(text.len), null);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;
    }

    pub fn bindInt(stmt: *c.sqlite3_stmt, idx: c_int, val: i64) !void {
        const rc = c.sqlite3_bind_int64(stmt, idx, val);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;
    }

    pub fn bindNull(stmt: *c.sqlite3_stmt, idx: c_int) !void {
        const rc = c.sqlite3_bind_null(stmt, idx);
        if (rc != c.SQLITE_OK) return DbError.BindFailed;
    }

    pub fn columnText(stmt: *c.sqlite3_stmt, idx: c_int) ?[]const u8 {
        const ptr = c.sqlite3_column_text(stmt, idx);
        if (ptr == null) return null;
        const len = c.sqlite3_column_bytes(stmt, idx);
        return ptr[0..@intCast(len)];
    }

    pub fn columnInt(stmt: *c.sqlite3_stmt, idx: c_int) i64 {
        return c.sqlite3_column_int64(stmt, idx);
    }

    pub fn columnIsNull(stmt: *c.sqlite3_stmt, idx: c_int) bool {
        return c.sqlite3_column_type(stmt, idx) == c.SQLITE_NULL;
    }

    pub fn finalize(stmt: *c.sqlite3_stmt) void {
        _ = c.sqlite3_finalize(stmt);
    }

    pub fn step(stmt: *c.sqlite3_stmt) c_int {
        return c.sqlite3_step(stmt);
    }

    pub fn stepRow(stmt: *c.sqlite3_stmt) bool {
        return c.sqlite3_step(stmt) == c.SQLITE_ROW;
    }

    pub fn stepDone(stmt: *c.sqlite3_stmt) bool {
        return c.sqlite3_step(stmt) == c.SQLITE_DONE;
    }

    fn ensureSchema(self: Database, allocator: std.mem.Allocator) !void {
        try schema.ensureSchema(self, allocator);
    }
};
