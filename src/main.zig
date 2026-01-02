const std = @import("std");
const db_core = @import("db/core.zig");
const plan_cmd = @import("commands/plan.zig");
const node_cmd = @import("commands/node.zig");
const refine_cmd = @import("commands/refine.zig");
const view_cmd = @import("commands/view.zig");
const fmt = @import("output/format.zig");

const Database = db_core.Database;
const DbError = db_core.DbError;
const Format = fmt.Format;
const MAX_DEPTH = node_cmd.MAX_DEPTH;

fn printUsage() void {
    fmt.eputs(
        \\Usage: planz <command> [options]
        \\
        \\Plans: create|delete|rename-plan|list|projects|delete-project|summarize
        \\Nodes: add|remove|rename|describe|move|refine|done|undone
        \\View:  show [--json|--xml|--md], progress
        \\
        \\Options: --project <path>, --desc <text>, --force, --to <path>, --after <sibling>
        \\Path:    Slash-separated, e.g. "Phase 1/Task A", max 4 levels
        \\Node ID: Use #<id> or path, e.g. "#5" or "Phase 1/Task A"
        \\
    );
}

fn commandNeedsWrite(command: []const u8) bool {
    const write_cmds = [_][]const u8{ "create", "rename-plan", "add", "remove", "rename", "describe", "move", "refine", "done", "undone", "summarize", "delete", "delete-project" };
    for (write_cmds) |cmd| {
        if (std.mem.eql(u8, command, cmd)) return true;
    }
    return false;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        std.process.exit(1);
    }

    const command = args[1];

    // Parse options
    var project: ?[]const u8 = null;
    var desc: ?[]const u8 = null;
    var summary: ?[]const u8 = null;
    var to_parent: ?[]const u8 = null;
    var after_sibling: ?[]const u8 = null;
    var force: bool = false;
    var format: Format = .text;

    var positional: std.ArrayListUnmanaged([]const u8) = .empty;
    defer positional.deinit(allocator);

    var add_children: std.ArrayListUnmanaged([]const u8) = .empty;
    defer add_children.deinit(allocator);

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--project")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --project requires a value\n");
                std.process.exit(1);
            }
            project = args[i];
        } else if (std.mem.eql(u8, arg, "--desc")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --desc requires a value\n");
                std.process.exit(1);
            }
            desc = args[i];
        } else if (std.mem.eql(u8, arg, "--summary")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --summary requires a value\n");
                std.process.exit(1);
            }
            summary = args[i];
        } else if (std.mem.eql(u8, arg, "--to")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --to requires a value\n");
                std.process.exit(1);
            }
            to_parent = args[i];
        } else if (std.mem.eql(u8, arg, "--after")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --after requires a value\n");
                std.process.exit(1);
            }
            after_sibling = args[i];
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--add")) {
            i += 1;
            if (i >= args.len) {
                fmt.eputs("Error: --add requires a value\n");
                std.process.exit(1);
            }
            try add_children.append(allocator, args[i]);
        } else if (std.mem.eql(u8, arg, "--json")) {
            format = .json;
        } else if (std.mem.eql(u8, arg, "--xml")) {
            format = .xml;
        } else if (std.mem.eql(u8, arg, "--md")) {
            format = .markdown;
        } else if (arg[0] != '-') {
            try positional.append(allocator, arg);
        }
    }

    // Resolve project path
    var resolved_project: []const u8 = undefined;
    {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const p = project orelse ".";
        resolved_project = try std.fs.cwd().realpath(p, &path_buf);
        resolved_project = try allocator.dupe(u8, resolved_project);
    }
    defer allocator.free(resolved_project);

    // Open database
    var db = Database.open(allocator, commandNeedsWrite(command)) catch |err| {
        fmt.eprint("Error: Failed to open database: {}\n", .{err});
        std.process.exit(2);
    };
    defer db.close();

    // Dispatch
    dispatch(db, allocator, command, positional.items, resolved_project, desc, summary, to_parent, after_sibling, force, format, add_children.items) catch |err| {
        handleError(err, if (positional.items.len > 0) positional.items[0] else command);
    };
}

fn dispatch(db: Database, allocator: std.mem.Allocator, command: []const u8, pos: [][]const u8, project: []const u8, desc: ?[]const u8, summary: ?[]const u8, to_parent: ?[]const u8, after_sibling: ?[]const u8, force: bool, format: Format, add_children: []const []const u8) !void {
    if (std.mem.eql(u8, command, "create")) {
        if (pos.len < 1) {
            fmt.eputs("Error: create requires <plan>\n");
            std.process.exit(1);
        }
        try plan_cmd.create(db, allocator, project, pos[0]);
    } else if (std.mem.eql(u8, command, "rename-plan")) {
        if (pos.len < 2) {
            fmt.eputs("Error: rename-plan requires <old-name> <new-name>\n");
            std.process.exit(1);
        }
        try plan_cmd.renamePlan(db, allocator, project, pos[0], pos[1]);
    } else if (std.mem.eql(u8, command, "delete")) {
        if (pos.len < 1) {
            fmt.eputs("Error: delete requires <plan>\n");
            std.process.exit(1);
        }
        try plan_cmd.delete(db, allocator, project, pos[0]);
    } else if (std.mem.eql(u8, command, "list")) {
        try plan_cmd.list(db, project);
    } else if (std.mem.eql(u8, command, "projects")) {
        try plan_cmd.projects(db);
    } else if (std.mem.eql(u8, command, "delete-project")) {
        try plan_cmd.deleteProject(db, allocator, project);
    } else if (std.mem.eql(u8, command, "summarize")) {
        if (pos.len < 1) {
            fmt.eputs("Error: summarize requires <plan>\n");
            std.process.exit(1);
        }
        const s = summary orelse {
            fmt.eputs("Error: summarize requires --summary\n");
            std.process.exit(1);
        };
        try plan_cmd.summarize(db, allocator, project, pos[0], s);
    } else if (std.mem.eql(u8, command, "add")) {
        if (pos.len < 2) {
            fmt.eputs("Error: add requires <plan> <path>\n");
            std.process.exit(1);
        }
        try node_cmd.add(db, allocator, project, pos[0], pos[1], desc);
    } else if (std.mem.eql(u8, command, "remove")) {
        if (pos.len < 2) {
            fmt.eputs("Error: remove requires <plan> <path>\n");
            std.process.exit(1);
        }
        try node_cmd.remove(db, allocator, project, pos[0], pos[1], force);
    } else if (std.mem.eql(u8, command, "rename")) {
        if (pos.len < 3) {
            fmt.eputs("Error: rename requires <plan> <path> <new-name>\n");
            std.process.exit(1);
        }
        try node_cmd.rename(db, allocator, project, pos[0], pos[1], pos[2]);
    } else if (std.mem.eql(u8, command, "describe")) {
        if (pos.len < 2) {
            fmt.eputs("Error: describe requires <plan> <path>\n");
            std.process.exit(1);
        }
        const d = desc orelse {
            fmt.eputs("Error: describe requires --desc\n");
            std.process.exit(1);
        };
        try node_cmd.describe(db, allocator, project, pos[0], pos[1], d);
    } else if (std.mem.eql(u8, command, "move")) {
        if (pos.len < 2) {
            fmt.eputs("Error: move requires <plan> <path>\n");
            std.process.exit(1);
        }
        if (to_parent == null and after_sibling == null) {
            fmt.eputs("Error: move requires --to or --after\n");
            std.process.exit(1);
        }
        try node_cmd.move(db, allocator, project, pos[0], pos[1], to_parent, after_sibling);
    } else if (std.mem.eql(u8, command, "refine")) {
        if (pos.len < 2) {
            fmt.eputs("Error: refine requires <plan> <path>\n");
            std.process.exit(1);
        }
        if (add_children.len == 0) {
            fmt.eputs("Error: refine requires at least one --add <child>\n");
            std.process.exit(1);
        }
        try refine_cmd.refine(db, allocator, project, pos[0], pos[1], add_children);
    } else if (std.mem.eql(u8, command, "done") or std.mem.eql(u8, command, "undone")) {
        if (pos.len < 2) {
            fmt.eputs("Error: done/undone requires <plan> <path>...\n");
            std.process.exit(1);
        }
        try node_cmd.done(db, allocator, project, pos[0], pos[1..], std.mem.eql(u8, command, "done"));
    } else if (std.mem.eql(u8, command, "show")) {
        if (pos.len < 1) {
            fmt.eputs("Error: show requires <plan>\n");
            std.process.exit(1);
        }
        const path = if (pos.len > 1) pos[1] else null;
        try view_cmd.show(db, allocator, project, pos[0], path, format);
    } else if (std.mem.eql(u8, command, "progress")) {
        if (pos.len < 1) {
            fmt.eputs("Error: progress requires <plan>\n");
            std.process.exit(1);
        }
        try view_cmd.progress(db, allocator, project, pos[0]);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        printUsage();
    } else {
        fmt.eprint("Error: Unknown command '{s}'\n\n", .{command});
        printUsage();
        std.process.exit(1);
    }
}

fn handleError(err: anytype, context: []const u8) void {
    switch (err) {
        DbError.NotFound => fmt.eprint("Error: '{s}' not found\n", .{context}),
        DbError.AlreadyExists => fmt.eprint("Error: '{s}' already exists\n", .{context}),
        DbError.DuplicateTitle => fmt.eputs("Error: Duplicate title at this level\n"),
        DbError.MaxDepthExceeded => fmt.eprint("Error: Max depth of {d} levels exceeded\n", .{MAX_DEPTH}),
        DbError.InvalidPath => fmt.eprint("Error: Invalid path '{s}'\n", .{context}),
        DbError.InvalidTitle => fmt.eputs("Error: Invalid title (empty or contains '/')\n"),
        DbError.HasChildren => fmt.eputs("Error: Node has children. Use --force to remove.\n"),
        DbError.LockFailed => fmt.eputs("Error: Could not acquire write lock\n"),
        DbError.TransactionFailed => fmt.eputs("Error: Transaction failed\n"),
        else => fmt.eprint("Error: {}\n", .{err}),
    }
    std.process.exit(1);
}
