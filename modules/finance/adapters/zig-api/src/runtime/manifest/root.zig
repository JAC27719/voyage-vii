const std = @import("std");
const platform = @import("../platform/root.zig");

pub const schema_version = 1;
pub const postgresql_version = "18.4";
pub const tigerbeetle_version = "0.17.7";
pub const postgresql_source_url = "https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2";
pub const postgresql_source_revision = "REL_18_4";
pub const tigerbeetle_release_url = "https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip";
pub const tigerbeetle_source_revision = "0.17.7";

pub const ManifestError = error{
    MalformedManifest,
    UnsupportedSchemaVersion,
    UnsupportedProductVersion,
    UnsupportedTarget,
    InvalidComponentOrder,
    InvalidComponentId,
    InvalidComponentVersion,
    InvalidRelativePath,
    InvalidSha256,
    InvalidLicensePath,
    InvalidSource,
    MissingComponent,
    HashMismatch,
    ExecutableFlagMissing,
    SecretInManifest,
};

pub const PackagedComponentId = enum {
    api,
    postgresql,
    tigerbeetle,
};

pub const Source = struct {
    kind: []const u8,
    url: ?[]const u8,
    revision: []const u8,
};

pub const PackagedComponent = struct {
    id: PackagedComponentId,
    version: []const u8,
    path: []const u8,
    sha256: []const u8,
    licensePath: ?[]const u8,
    source: Source,
};

pub const PackagedManifest = struct {
    schemaVersion: u32,
    productVersion: []const u8,
    target: []const u8,
    components: []const PackagedComponent,
};

pub const WritableComponents = struct {
    postgresql: []const u8,
    tigerbeetle: []const u8,
};

pub const WritableManifest = struct {
    schemaVersion: u32,
    productVersion: []const u8,
    target: []const u8,
    createdAt: []const u8,
    components: WritableComponents,
};

pub fn validatePackagedManifest(manifest: PackagedManifest, expected_product_version: []const u8) ManifestError!void {
    try validateHeader(manifest.schemaVersion, manifest.productVersion, expected_product_version, manifest.target);
    if (manifest.components.len != 3) return error.MissingComponent;
    const expected = [_]PackagedComponentId{ .api, .postgresql, .tigerbeetle };
    for (manifest.components, expected) |component, id| {
        if (component.id != id) return error.InvalidComponentOrder;
        try validateComponent(component, expected_product_version);
    }
}

pub fn parseAndValidatePackagedManifest(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(PackagedManifest) {
    var parsed = std.json.parseFromSlice(PackagedManifest, allocator, bytes, .{
        .ignore_unknown_fields = false,
    }) catch return error.MalformedManifest;
    errdefer parsed.deinit();
    const expected_product_version = try readProductVersion(allocator);
    defer allocator.free(expected_product_version);
    try validatePackagedManifest(parsed.value, expected_product_version);
    return parsed;
}

pub fn validateWritableManifest(manifest: WritableManifest, expected_product_version: []const u8) ManifestError!void {
    try validateHeader(manifest.schemaVersion, manifest.productVersion, expected_product_version, manifest.target);
    if (!isRfc3339Utc(manifest.createdAt)) return error.MalformedManifest;
    if (!std.mem.eql(u8, manifest.components.postgresql, postgresql_version) or
        !std.mem.eql(u8, manifest.components.tigerbeetle, tigerbeetle_version))
    {
        return error.MissingComponent;
    }
}

pub fn parseAndValidateWritableManifest(
    allocator: std.mem.Allocator,
    bytes: []const u8,
) !std.json.Parsed(WritableManifest) {
    var parsed = std.json.parseFromSlice(WritableManifest, allocator, bytes, .{
        .ignore_unknown_fields = true,
    }) catch return error.MalformedManifest;
    errdefer parsed.deinit();
    const expected_product_version = try readProductVersion(allocator);
    defer allocator.free(expected_product_version);
    try validateWritableManifest(parsed.value, expected_product_version);
    return parsed;
}

pub fn verifyComponentBytes(component: PackagedComponent, bytes: []const u8) !void {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &hex, component.sha256)) return error.HashMismatch;
}

pub fn validateExecutableFlag(component: PackagedComponent) ManifestError!void {
    switch (component.id) {
        .api, .tigerbeetle => {
            if (!std.mem.endsWith(u8, component.path, ".exe")) return error.ExecutableFlagMissing;
        },
        .postgresql => {},
    }
}

pub fn readProductVersion(allocator: std.mem.Allocator) ![]u8 {
    const paths = [_][]const u8{
        "VERSION",
        "../../../../VERSION",
    };
    for (paths) |path| {
        const bytes = std.fs.cwd().readFileAlloc(allocator, path, 64) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        errdefer allocator.free(bytes);
        const trimmed = std.mem.trimRight(u8, bytes, "\r\n");
        if (trimmed.len != bytes.len) {
            const dupe = try allocator.dupe(u8, trimmed);
            allocator.free(bytes);
            return dupe;
        }
        return bytes;
    }
    return error.FileNotFound;
}

fn validateHeader(version: u32, manifest_product_version: []const u8, expected_product_version: []const u8, target: []const u8) ManifestError!void {
    if (version != schema_version) return error.UnsupportedSchemaVersion;
    if (!std.mem.eql(u8, manifest_product_version, expected_product_version)) return error.UnsupportedProductVersion;
    if (!std.mem.eql(u8, target, platform.current_target)) return error.UnsupportedTarget;
}

fn validateComponent(component: PackagedComponent, expected_product_version: []const u8) ManifestError!void {
    if (component.version.len == 0) return error.InvalidComponentVersion;
    try validateRelativePosixPath(component.path);
    try validateSha256(component.sha256);
    try validateExecutableFlag(component);
    try validateSource(component);
    switch (component.id) {
        .api => {
            if (!std.mem.eql(u8, component.version, expected_product_version)) return error.InvalidComponentVersion;
            if (component.licensePath != null) return error.InvalidLicensePath;
        },
        .postgresql, .tigerbeetle => {
            const license_path = component.licensePath orelse return error.InvalidLicensePath;
            try validateRelativePosixPath(license_path);
        },
    }
    try rejectSecretLikeText(component.path);
    try rejectSecretLikeText(component.sha256);
    if (component.licensePath) |license_path| try rejectSecretLikeText(license_path);
    try rejectSecretLikeText(component.source.revision);
    if (component.source.url) |url| try rejectSecretLikeText(url);
}

fn validateSource(component: PackagedComponent) ManifestError!void {
    if (component.source.revision.len == 0) return error.InvalidSource;
    switch (component.id) {
        .api => {
            if (!std.mem.eql(u8, component.source.kind, "first-party-build")) return error.InvalidSource;
            if (component.source.url != null) return error.InvalidSource;
            if (!isLowerHex(component.source.revision) or component.source.revision.len != 40) return error.InvalidSource;
        },
        .postgresql, .tigerbeetle => {
            const expected_version = switch (component.id) {
                .postgresql => postgresql_version,
                .tigerbeetle => tigerbeetle_version,
                .api => unreachable,
            };
            if (!std.mem.eql(u8, component.version, expected_version)) return error.InvalidComponentVersion;
            if (!std.mem.eql(u8, component.source.kind, "official-source") and
                !std.mem.eql(u8, component.source.kind, "official-release"))
            {
                return error.InvalidSource;
            }
            const url = component.source.url orelse return error.InvalidSource;
            if (!std.mem.startsWith(u8, url, "https://")) return error.InvalidSource;
            switch (component.id) {
                .postgresql => {
                    if (!std.mem.eql(u8, component.source.kind, "official-source")) return error.InvalidSource;
                    if (!std.mem.eql(u8, url, postgresql_source_url)) return error.InvalidSource;
                    if (!std.mem.eql(u8, component.source.revision, postgresql_source_revision)) return error.InvalidSource;
                },
                .tigerbeetle => {
                    if (!std.mem.eql(u8, component.source.kind, "official-release")) return error.InvalidSource;
                    if (!std.mem.eql(u8, url, tigerbeetle_release_url)) return error.InvalidSource;
                    if (!std.mem.eql(u8, component.source.revision, tigerbeetle_source_revision)) return error.InvalidSource;
                },
                .api => unreachable,
            }
        },
    }
}

fn validateRelativePosixPath(path: []const u8) ManifestError!void {
    if (path.len == 0) return error.InvalidRelativePath;
    if (std.fs.path.isAbsolute(path)) return error.InvalidRelativePath;
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return error.InvalidRelativePath;
    if (std.mem.indexOf(u8, path, "//") != null) return error.InvalidRelativePath;
    var it = std.mem.tokenizeScalar(u8, path, '/');
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.InvalidRelativePath;
    }
}

fn validateSha256(hash: []const u8) ManifestError!void {
    if (hash.len != 64 or !isLowerHex(hash)) return error.InvalidSha256;
}

fn isLowerHex(value: []const u8) bool {
    for (value) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) return false;
    }
    return true;
}

fn isRfc3339Utc(value: []const u8) bool {
    return value.len == 20 and
        allDigits(value[0..4]) and allDigits(value[5..7]) and allDigits(value[8..10]) and
        allDigits(value[11..13]) and allDigits(value[14..16]) and allDigits(value[17..19]) and
        value[4] == '-' and value[7] == '-' and value[10] == 'T' and
        value[13] == ':' and value[16] == ':' and value[19] == 'Z';
}

fn allDigits(value: []const u8) bool {
    for (value) |byte| {
        if (!std.ascii.isDigit(byte)) return false;
    }
    return true;
}

fn rejectSecretLikeText(value: []const u8) ManifestError!void {
    const needles = [_][]const u8{
        "secret",
        "password",
        "token",
        "credential",
        "authorization",
        "bearer",
        "C:\\",
        "Users/",
        "Users\\",
    };
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(value, needle) != null) return error.SecretInManifest;
    }
}

pub fn selfTest() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const packaged =
        \\{
        \\  "schemaVersion": 1,
        \\  "productVersion": "0.1.0",
        \\  "target": "x86_64-pc-windows-msvc",
        \\  "components": [
        \\    {
        \\      "id": "api",
        \\      "version": "0.1.0",
        \\      "path": "api/voyage-vii-api.exe",
        \\      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        \\      "licensePath": null,
        \\      "source": {
        \\        "kind": "first-party-build",
        \\        "url": null,
        \\        "revision": "0123456789abcdef0123456789abcdef01234567"
        \\      }
        \\    },
        \\    {
        \\      "id": "postgresql",
        \\      "version": "18.4",
        \\      "path": "postgresql/bin/postgres.exe",
        \\      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        \\      "licensePath": "licenses/postgresql/LICENSE",
        \\      "source": {
        \\        "kind": "official-source",
        \\        "url": "https://ftp.postgresql.org/pub/source/v18.4/postgresql-18.4.tar.bz2",
        \\        "revision": "REL_18_4"
        \\      }
        \\    },
        \\    {
        \\      "id": "tigerbeetle",
        \\      "version": "0.17.7",
        \\      "path": "tigerbeetle/tigerbeetle.exe",
        \\      "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        \\      "licensePath": "licenses/tigerbeetle/LICENSE",
        \\      "source": {
        \\        "kind": "official-release",
        \\        "url": "https://github.com/tigerbeetle/tigerbeetle/releases/download/0.17.7/tigerbeetle-x86_64-windows.zip",
        \\        "revision": "0.17.7"
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    var parsed_packaged = try parseAndValidatePackagedManifest(allocator, packaged);
    defer parsed_packaged.deinit();
    try verifyComponentBytes(parsed_packaged.value.components[0], "test");

    const writable =
        \\{
        \\  "schemaVersion": 1,
        \\  "productVersion": "0.1.0",
        \\  "target": "x86_64-pc-windows-msvc",
        \\  "createdAt": "2026-06-30T12:00:00Z",
        \\  "components": {
        \\    "postgresql": "18.4",
        \\    "tigerbeetle": "0.17.7"
        \\  }
        \\}
    ;
    var parsed_writable = try parseAndValidateWritableManifest(allocator, writable);
    defer parsed_writable.deinit();

    const wrong_target = "{\"schemaVersion\":1,\"productVersion\":\"0.1.0\",\"target\":\"x86_64-unknown-linux-gnu\",\"components\":[]}";
    try expectManifestError(error.UnsupportedTarget, parseAndValidatePackagedManifest(allocator, wrong_target));
    const malformed = "{\"schemaVersion\":1";
    try expectManifestError(error.MalformedManifest, parseAndValidateWritableManifest(allocator, malformed));
}

fn expectManifestError(expected: anyerror, actual: anytype) !void {
    if (actual) |parsed| {
        parsed.deinit();
        return error.SelfTestFailed;
    } else |err| {
        if (err == expected) return;
        return err;
    }
}
