const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_options = .{ .target = target, .optimize = optimize };

    const api_dep = b.dependency("api", dep_options);
    const sqlite_amalgamation = b.option(
        []const u8,
        "sqlite-amalgamation",
        "Absolute path to verified SQLite 3.53.3 amalgamation directory",
    ) orelse "../../../../spikes/sqlite/source/sqlite-amalgamation-3530300";
    const tb_client_lib = b.option(
        []const u8,
        "tb-client-lib",
        "Absolute path to the approved TigerBeetle 0.17.7 static C client library",
    );
    const tb_client_include = b.option(
        []const u8,
        "tb-client-include",
        "Absolute path to the approved TigerBeetle 0.17.7 C client include directory",
    );
    const tb_native = tigerBeetleNativeInputs(tb_client_lib, tb_client_include);
    const native_options = b.addOptions();
    native_options.addOption(bool, "tigerbeetle_client_enabled", tb_native.enabled);

    const executable = b.addExecutable(.{
        .name = "voyage-vii-api",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    executable.root_module.addImport("api", api_dep.module("api"));
    executable.root_module.addOptions("native_inputs", native_options);
    executable.linkLibC();
    configureSQLite(executable, sqlite_amalgamation);
    configureTigerBeetleNative(executable, target, tb_native);
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/all.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addImport("api", api_dep.module("api"));
    tests.root_module.addImport("app", executable.root_module);
    tests.root_module.addOptions("native_inputs", native_options);
    tests.linkLibC();
    configureSQLite(tests, sqlite_amalgamation);
    configureTigerBeetleNative(tests, target, tb_native);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run API contract and seam tests");
    test_step.dependOn(&run_tests.step);
}

fn configureSQLite(artifact: *std.Build.Step.Compile, sqlite_amalgamation: []const u8) void {
    artifact.root_module.addIncludePath(.{ .cwd_relative = sqlite_amalgamation });
    artifact.addCSourceFile(.{
        .file = .{ .cwd_relative = std.fs.path.join(
            artifact.step.owner.allocator,
            &.{ sqlite_amalgamation, "sqlite3.c" },
        ) catch @panic("unable to join SQLite source path") },
    });
}

const TigerBeetleNativeInputs = struct {
    enabled: bool,
    client_lib: ?[]const u8,
    client_include: ?[]const u8,
};

fn tigerBeetleNativeInputs(
    client_lib: ?[]const u8,
    client_include: ?[]const u8,
) TigerBeetleNativeInputs {
    if ((client_lib == null) != (client_include == null)) {
        @panic("-Dtb-client-lib and -Dtb-client-include must be supplied together");
    }
    return .{
        .enabled = client_lib != null,
        .client_lib = client_lib,
        .client_include = client_include,
    };
}

fn configureTigerBeetleNative(
    artifact: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    native: TigerBeetleNativeInputs,
) void {
    if (!native.enabled) return;
    artifact.root_module.addIncludePath(.{ .cwd_relative = native.client_include.? });
    artifact.root_module.addObjectFile(.{ .cwd_relative = native.client_lib.? });
    switch (target.result.os.tag) {
        .windows => {
            artifact.linkSystemLibrary("advapi32");
            artifact.linkSystemLibrary("ws2_32");
        },
        else => {},
    }
}
