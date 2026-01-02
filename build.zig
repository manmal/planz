const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "planz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    // Use bundled sqlite3 for cross-compilation, system lib otherwise
    const use_bundled = b.option(bool, "bundled-sqlite", "Use bundled SQLite3 amalgamation") orelse false;

    if (use_bundled) {
        exe.addCSourceFile(.{
            .file = b.path("vendor/sqlite3.c"),
            .flags = &.{
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_ENABLE_FTS5",
                "-DSQLITE_ENABLE_RTREE",
                "-DSQLITE_ENABLE_JSON1",
            },
        });
        exe.addIncludePath(b.path("vendor"));
    } else {
        exe.linkSystemLibrary("sqlite3");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run planz");
    run_step.dependOn(&run_cmd.step);
}
