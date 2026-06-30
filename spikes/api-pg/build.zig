const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_options = .{ .target = target, .optimize = optimize };

    const executable = b.addExecutable(.{
        .name = "api-pg-spike",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    executable.root_module.addImport("api", b.dependency("api", dep_options).module("api"));

    const pg_dep = b.dependency("pg", dep_options);
    const apply_pg_patch = b.addSystemCommand(&.{
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
    });
    apply_pg_patch.addFileArg(b.path("scripts/apply-pg-patch.ps1"));
    apply_pg_patch.addDirectoryArg(pg_dep.path("."));
    apply_pg_patch.addFileArg(b.path("../../patches/pg.zig/windows-connect-timeout.patch"));
    const patched_pg = apply_pg_patch.addOutputDirectoryArg("pg-patched");

    const upstream_pg_module = pg_dep.module("pg");
    const patched_pg_module = b.createModule(.{
        .root_source_file = patched_pg.path(b, "src/pg.zig"),
        .target = target,
        .optimize = optimize,
    });
    patched_pg_module.addImport("buffer", upstream_pg_module.import_table.get("buffer").?);
    patched_pg_module.addImport("metrics", upstream_pg_module.import_table.get("metrics").?);
    const pg_options = b.addOptions();
    pg_options.addOption(bool, "openssl", false);
    pg_options.addOption(bool, "column_names", false);
    patched_pg_module.addOptions("config", pg_options);
    executable.root_module.addImport("pg", patched_pg_module);

    b.installArtifact(executable);
}
