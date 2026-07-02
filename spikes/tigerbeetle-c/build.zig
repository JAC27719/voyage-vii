const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const client_lib = b.option(
        []const u8,
        "tb-client-lib",
        "Absolute path to the TigerBeetle 0.17.7 static C client library",
    ) orelse @panic("-Dtb-client-lib is required");
    const client_include = b.option(
        []const u8,
        "tb-client-include",
        "Absolute path to the directory containing TigerBeetle 0.17.7 tb_client.h",
    ) orelse @panic("-Dtb-client-include is required");

    const exe = b.addExecutable(.{
        .name = "tigerbeetle-c-spike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addIncludePath(.{ .cwd_relative = client_include });
    exe.root_module.addObjectFile(.{ .cwd_relative = client_lib });
    exe.linkLibC();

    switch (target.result.os.tag) {
        .windows => {
            exe.linkSystemLibrary("advapi32");
            exe.linkSystemLibrary("ws2_32");
        },
        else => {},
    }

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Run one native C ABI evidence scenario");
    run_step.dependOn(&run.step);
}
