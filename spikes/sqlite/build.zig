const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite_amalgamation = b.option(
        []const u8,
        "sqlite-amalgamation",
        "Absolute path to the verified SQLite amalgamation directory containing sqlite3.c and sqlite3.h",
    ) orelse @panic("-Dsqlite-amalgamation is required");

    const exe = b.addExecutable(.{
        .name = "sqlite-spike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addIncludePath(.{ .cwd_relative = sqlite_amalgamation });
    exe.addCSourceFile(.{
        .file = .{ .cwd_relative = b.pathJoin(&.{ sqlite_amalgamation, "sqlite3.c" }) },
    });
    exe.linkLibC();

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Run SQLite native evidence scenario");
    run_step.dependOn(&run.step);
}
