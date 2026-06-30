const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_options = .{ .target = target, .optimize = optimize };

    const api_dep = b.dependency("api", dep_options);
    const pg_module = patchedPgModule(b, target, optimize, dep_options);
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
    executable.root_module.addImport("pg", pg_module);
    executable.root_module.addOptions("native_inputs", native_options);
    executable.linkLibC();
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
    tests.root_module.addImport("pg", pg_module);
    tests.root_module.addImport("app", executable.root_module);
    tests.root_module.addOptions("native_inputs", native_options);
    tests.linkLibC();
    configureTigerBeetleNative(tests, target, tb_native);

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run API contract and seam tests");
    test_step.dependOn(&run_tests.step);
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

fn patchedPgModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dep_options: anytype,
) *std.Build.Module {
    const pg_dep = b.dependency("pg", dep_options);
    const patch_command =
        \\& {
        \\param([string]$sourceArg, [string]$patchArg, [string]$outputArg)
        \\$ErrorActionPreference = 'Stop'
        \\$source = (Resolve-Path -LiteralPath $sourceArg).Path
        \\$patch = (Resolve-Path -LiteralPath $patchArg).Path
        \\$output = $outputArg
        \\function Sha256Lower($path) {
        \\  $stream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $path))
        \\  try {
        \\    $sha = [Security.Cryptography.SHA256]::Create()
        \\    try { return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
        \\    finally { $sha.Dispose() }
        \\  }
        \\  finally { $stream.Dispose() }
        \\}
        \\$expectedStream = '91d1ab1b4ed1a456b1bd9f5d9b68ff327eca036ecc6db4dddf8889af21e28abe'
        \\$expectedPatch = '02d6791ab6bdb147c34972e0076992840be7e5fea2e51e6cdac94455033c578c'
        \\if ((Sha256Lower $patch) -ne $expectedPatch) { throw 'pg.zig patch SHA-256 mismatch' }
        \\if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Recurse -Force }
        \\New-Item -ItemType Directory -Force -Path $output | Out-Null
        \\Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $output -Recurse -Force
        \\$repoRoot = (git rev-parse --show-toplevel).Trim()
        \\if ($LASTEXITCODE -ne 0) { throw 'unable to resolve Git repository root' }
        \\Push-Location $repoRoot
        \\try {
        \\  $gitOutput = (Resolve-Path -LiteralPath $output -Relative).TrimStart('.', '\', '/').Replace('\', '/')
        \\}
        \\finally {
        \\  Pop-Location
        \\}
        \\$streamPath = Join-Path $output 'src/stream.zig'
        \\if ((Sha256Lower $streamPath) -ne $expectedStream) { throw 'pg.zig upstream src/stream.zig hash mismatch' }
        \\git apply --check --unidiff-zero --whitespace=nowarn --directory=$gitOutput $patch
        \\if ($LASTEXITCODE -ne 0) { throw 'pg.zig patch check failed' }
        \\git apply --unidiff-zero --whitespace=nowarn --directory=$gitOutput $patch
        \\if ($LASTEXITCODE -ne 0) { throw 'pg.zig patch application failed' }
        \\}
    ;

    const apply_pg_patch = b.addSystemCommand(&.{
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        patch_command,
    });
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
    return patched_pg_module;
}
