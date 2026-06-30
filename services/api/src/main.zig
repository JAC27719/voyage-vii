const std = @import("std");
const builtin = @import("builtin");
const api = @import("api");
const pg = @import("pg");

const postgres = @import("postgres/root.zig");
const tigerbeetle = @import("tigerbeetle/root.zig");
const http = @import("http/root.zig");
const status = @import("status/root.zig");
const runtime_platform = @import("runtime/platform/root.zig");
const runtime_manifest = @import("runtime/manifest/root.zig");
const runtime_logging = @import("runtime/logging/root.zig");
const runtime_postgresql = @import("runtime/postgresql/root.zig");
const runtime_tigerbeetle = @import("runtime/tigerbeetle/root.zig");
const runtime_supervisor = @import("runtime/supervisor/root.zig");

pub const product_version = "0.1.0";
pub const executable_name = "voyage-vii-api";
pub const windows_target = "x86_64-pc-windows-msvc";
pub const packaged_origin = "http://tauri.localhost";
pub const development_origin = "http://localhost:1420";
pub const handshake_prefix = "VOYAGE_VII_HANDSHAKE ";
pub const handshake_protocol_version = 1;
pub const handshake_timeout_seconds = 15;
pub const handshake_max_bytes = 16 * 1024;
pub const token_raw_len = 32;
pub const token_encoded_len = std.base64.url_safe_no_pad.Encoder.calcSize(token_raw_len);

const ApiImport = api;
const PgImport = pg;

pub const ExitCode = enum(u8) {
    ok = 0,
    configuration_failure = 2,
    data_root_lock_failure = 3,
    runtime_asset_failure = 4,
    bind_or_startup_failure = 5,
    self_test_failure = 6,
    native_shutdown_timeout = 7,
};

pub const RuntimeMode = enum {
    managed,
    external,
};

pub const ConfigError = error{
    MissingCommand,
    UnknownCommand,
    InvalidArguments,
    MissingRequiredFlag,
    DuplicateFlag,
    UnknownFlag,
    InvalidRuntime,
    PathMustBeAbsolute,
    InvalidHandshake,
    InvalidOrigin,
    InvalidListen,
    InvalidAdvertisedApiUrl,
    MissingExternalFlag,
    ManagedModeRejectedExternalFlag,
    DevelopmentContainerRequiresExternalMode,
    NonLoopbackListenRequiresDevelopmentContainer,
    PasswordFileMustBeAbsolute,
};

pub const Command = union(enum) {
    serve: ServeConfig,
    self_test,
    version,
};

pub const ExternalDatabaseConfig = struct {
    postgres_host: []const u8,
    postgres_port: u16,
    postgres_database: []const u8,
    postgres_user: []const u8,
    postgres_password_file: []const u8,
    tigerbeetle_address: []const u8,
};

pub const ServeConfig = struct {
    runtime: RuntimeMode,
    runtime_root: []const u8,
    data_root: []const u8,
    allowed_origin: []const u8,
    handshake: []const u8,
    listen: ListenAddress,
    advertised_api_url: ?[]const u8,
    development_container: bool,
    external: ?ExternalDatabaseConfig,
};

pub const ListenAddress = struct {
    host: []const u8,
    port: u16,

    pub fn default() ListenAddress {
        return .{ .host = "127.0.0.1", .port = 0 };
    }
};

pub const BoundEndpoint = struct {
    api_url: []const u8,
};

pub const TokenPair = struct {
    app_token: [token_encoded_len]u8,
    supervisor_token: [token_encoded_len]u8,
};

pub fn main() void {
    runMain() catch |err| {
        const code = exitCodeForError(err);
        std.debug.print("api_exit=failed code={s}\n", .{@errorName(err)});
        std.process.exit(@intFromEnum(code));
    };
}

fn runMain() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const command = try parseCommand(args[1..]);
    switch (command) {
        .version => {
            try std.fs.File.stdout().writeAll(product_version ++ "\n");
        },
        .self_test => try runSelfTest(),
        .serve => |config| try serve(allocator, config),
    }
}

pub fn parseCommand(args: []const []const u8) ConfigError!Command {
    if (args.len == 0) return error.MissingCommand;
    if (std.mem.eql(u8, args[0], "version")) {
        if (args.len != 1) return error.InvalidArguments;
        return .version;
    }
    if (std.mem.eql(u8, args[0], "self-test")) {
        if (args.len != 1) return error.InvalidArguments;
        return .self_test;
    }
    if (std.mem.eql(u8, args[0], "serve")) {
        return .{ .serve = try parseServe(args[1..]) };
    }
    return error.UnknownCommand;
}

pub fn parseServe(args: []const []const u8) ConfigError!ServeConfig {
    var runtime: ?RuntimeMode = null;
    var runtime_root: ?[]const u8 = null;
    var data_root: ?[]const u8 = null;
    var allowed_origin: ?[]const u8 = null;
    var handshake: ?[]const u8 = null;
    var listen: ListenAddress = ListenAddress.default();
    var listen_seen = false;
    var advertised_api_url: ?[]const u8 = null;
    var development_container = false;
    var postgres_host: ?[]const u8 = null;
    var postgres_port: ?u16 = null;
    var postgres_database: ?[]const u8 = null;
    var postgres_user: ?[]const u8 = null;
    var postgres_password_file: ?[]const u8 = null;
    var tigerbeetle_address: ?[]const u8 = null;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        if (std.mem.eql(u8, flag, "--development-container")) {
            if (development_container) return error.DuplicateFlag;
            development_container = true;
            continue;
        }

        index += 1;
        if (index >= args.len) return error.MissingRequiredFlag;
        const value = args[index];

        if (std.mem.eql(u8, flag, "--runtime")) {
            if (runtime != null) return error.DuplicateFlag;
            runtime = parseRuntime(value) orelse return error.InvalidRuntime;
        } else if (std.mem.eql(u8, flag, "--runtime-root")) {
            if (runtime_root != null) return error.DuplicateFlag;
            if (!std.fs.path.isAbsolute(value)) return error.PathMustBeAbsolute;
            runtime_root = value;
        } else if (std.mem.eql(u8, flag, "--data-root")) {
            if (data_root != null) return error.DuplicateFlag;
            if (!std.fs.path.isAbsolute(value)) return error.PathMustBeAbsolute;
            data_root = value;
        } else if (std.mem.eql(u8, flag, "--allowed-origin")) {
            if (allowed_origin != null) return error.DuplicateFlag;
            if (!isAllowedOrigin(value)) return error.InvalidOrigin;
            allowed_origin = value;
        } else if (std.mem.eql(u8, flag, "--handshake")) {
            if (handshake != null) return error.DuplicateFlag;
            if (!std.mem.eql(u8, value, "stdout-v1")) return error.InvalidHandshake;
            handshake = value;
        } else if (std.mem.eql(u8, flag, "--listen")) {
            if (listen_seen) return error.DuplicateFlag;
            listen = try parseListen(value);
            listen_seen = true;
        } else if (std.mem.eql(u8, flag, "--advertised-api-url")) {
            if (advertised_api_url != null) return error.DuplicateFlag;
            if (!isValidApiUrl(value)) return error.InvalidAdvertisedApiUrl;
            advertised_api_url = value;
        } else if (std.mem.eql(u8, flag, "--postgres-host")) {
            if (postgres_host != null) return error.DuplicateFlag;
            postgres_host = value;
        } else if (std.mem.eql(u8, flag, "--postgres-port")) {
            if (postgres_port != null) return error.DuplicateFlag;
            postgres_port = std.fmt.parseInt(u16, value, 10) catch return error.InvalidArguments;
        } else if (std.mem.eql(u8, flag, "--postgres-database")) {
            if (postgres_database != null) return error.DuplicateFlag;
            postgres_database = value;
        } else if (std.mem.eql(u8, flag, "--postgres-user")) {
            if (postgres_user != null) return error.DuplicateFlag;
            postgres_user = value;
        } else if (std.mem.eql(u8, flag, "--postgres-password-file")) {
            if (postgres_password_file != null) return error.DuplicateFlag;
            if (!std.fs.path.isAbsolute(value)) return error.PasswordFileMustBeAbsolute;
            postgres_password_file = value;
        } else if (std.mem.eql(u8, flag, "--tigerbeetle-address")) {
            if (tigerbeetle_address != null) return error.DuplicateFlag;
            tigerbeetle_address = value;
        } else {
            return error.UnknownFlag;
        }
    }

    const mode = runtime orelse return error.MissingRequiredFlag;
    const origin = allowed_origin orelse return error.MissingRequiredFlag;
    const config = ServeConfig{
        .runtime = mode,
        .runtime_root = runtime_root orelse return error.MissingRequiredFlag,
        .data_root = data_root orelse return error.MissingRequiredFlag,
        .allowed_origin = origin,
        .handshake = handshake orelse return error.MissingRequiredFlag,
        .listen = listen,
        .advertised_api_url = advertised_api_url,
        .development_container = development_container,
        .external = null,
    };

    if (development_container and mode != .external) {
        return error.DevelopmentContainerRequiresExternalMode;
    }
    if (!isLoopbackListen(listen.host) and !(mode == .external and development_container)) {
        return error.NonLoopbackListenRequiresDevelopmentContainer;
    }

    const any_external = postgres_host != null or postgres_port != null or postgres_database != null or
        postgres_user != null or postgres_password_file != null or tigerbeetle_address != null;
    if (mode == .managed) {
        if (development_container or any_external) return error.ManagedModeRejectedExternalFlag;
        return config;
    }

    return .{
        .runtime = mode,
        .runtime_root = config.runtime_root,
        .data_root = config.data_root,
        .allowed_origin = config.allowed_origin,
        .handshake = config.handshake,
        .listen = config.listen,
        .advertised_api_url = config.advertised_api_url,
        .development_container = config.development_container,
        .external = .{
            .postgres_host = postgres_host orelse return error.MissingExternalFlag,
            .postgres_port = postgres_port orelse return error.MissingExternalFlag,
            .postgres_database = postgres_database orelse return error.MissingExternalFlag,
            .postgres_user = postgres_user orelse return error.MissingExternalFlag,
            .postgres_password_file = postgres_password_file orelse return error.MissingExternalFlag,
            .tigerbeetle_address = tigerbeetle_address orelse return error.MissingExternalFlag,
        },
    };
}

fn parseRuntime(value: []const u8) ?RuntimeMode {
    if (std.mem.eql(u8, value, "managed")) return .managed;
    if (std.mem.eql(u8, value, "external")) return .external;
    return null;
}

pub fn parseListen(value: []const u8) ConfigError!ListenAddress {
    const colon = std.mem.lastIndexOfScalar(u8, value, ':') orelse return error.InvalidListen;
    if (colon == 0 or colon == value.len - 1) return error.InvalidListen;
    const host = value[0..colon];
    const port = std.fmt.parseInt(u16, value[colon + 1 ..], 10) catch return error.InvalidListen;
    if (std.mem.indexOfScalar(u8, host, ':') != null) return error.InvalidListen;
    _ = std.net.Address.parseIp(host, port) catch return error.InvalidListen;
    return .{ .host = host, .port = port };
}

pub fn isAllowedOrigin(origin: []const u8) bool {
    return std.mem.eql(u8, origin, packaged_origin) or std.mem.eql(u8, origin, development_origin);
}

pub fn isLoopbackListen(host: []const u8) bool {
    return std.mem.eql(u8, host, "127.0.0.1") or std.mem.eql(u8, host, "localhost") or std.mem.eql(u8, host, "::1");
}

pub fn isValidApiUrl(url: []const u8) bool {
    const prefix = "http://";
    if (!std.mem.startsWith(u8, url, prefix)) return false;
    const authority = url[prefix.len..];
    if (authority.len == 0) return false;
    if (std.mem.indexOfAny(u8, authority, "/?#@") != null) return false;
    const colon = std.mem.lastIndexOfScalar(u8, authority, ':');
    const host = if (colon) |idx| authority[0..idx] else authority;
    if (host.len == 0) return false;
    return isLoopbackListen(host);
}

fn serve(allocator: std.mem.Allocator, config: ServeConfig) !void {
    var server = try bindServer(config.listen);
    defer server.deinit();

    const endpoint = try boundEndpoint(allocator, config, server.listen_address);
    defer allocator.free(endpoint.api_url);

    const tokens = generateTokens();
    try emitHandshake(endpoint.api_url, tokens);
    std.debug.print("api_state=launching runtime={s}\n", .{@tagName(config.runtime)});

    while (true) {
        var connection = server.accept() catch |err| {
            std.debug.print("api_accept=failed error={s}\n", .{@errorName(err)});
            continue;
        };
        defer connection.stream.close();
        try connection.stream.writeAll("HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n");
    }
}

fn bindServer(listen: ListenAddress) !std.net.Server {
    const address = try std.net.Address.parseIp(listen.host, listen.port);
    return try address.listen(.{ .reuse_address = true });
}

pub fn boundEndpoint(allocator: std.mem.Allocator, config: ServeConfig, address: std.net.Address) !BoundEndpoint {
    if (config.advertised_api_url) |url| {
        if (!isValidApiUrl(url)) return error.InvalidAdvertisedApiUrl;
        return .{ .api_url = try allocator.dupe(u8, url) };
    }
    return .{ .api_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{address.getPort()}) };
}

pub fn generateTokens() TokenPair {
    var app_raw: [token_raw_len]u8 = undefined;
    var supervisor_raw: [token_raw_len]u8 = undefined;
    std.crypto.random.bytes(&app_raw);
    std.crypto.random.bytes(&supervisor_raw);
    while (std.mem.eql(u8, &app_raw, &supervisor_raw)) {
        std.crypto.random.bytes(&supervisor_raw);
    }
    var tokens: TokenPair = undefined;
    _ = std.base64.url_safe_no_pad.Encoder.encode(&tokens.app_token, &app_raw);
    _ = std.base64.url_safe_no_pad.Encoder.encode(&tokens.supervisor_token, &supervisor_raw);
    @memset(&app_raw, 0);
    @memset(&supervisor_raw, 0);
    return tokens;
}

pub fn emitHandshake(api_url: []const u8, tokens: TokenPair) !void {
    var buffer: [handshake_max_bytes]u8 = undefined;
    const line = try std.fmt.bufPrint(
        &buffer,
        handshake_prefix ++ "{{\"protocolVersion\":1,\"apiUrl\":\"{s}\",\"appToken\":\"{s}\",\"supervisorToken\":\"{s}\"}}\n",
        .{ api_url, tokens.app_token, tokens.supervisor_token },
    );
    if (line.len > handshake_max_bytes) return error.HandshakeTooLarge;
    try std.fs.File.stdout().writeAll(line);
}

pub fn runSelfTest() !void {
    _ = ApiImport;
    _ = PgImport;
    try postgres.selfTest();
    try tigerbeetle.selfTest();
    try http.selfTest();
    try status.selfTest();
    try runtime_platform.selfTest();
    try runtime_manifest.selfTest();
    try runtime_logging.selfTest();
    try runtime_postgresql.selfTest();
    try runtime_tigerbeetle.selfTest();
    try runtime_supervisor.selfTest();
}

pub fn exitCodeForError(err: anyerror) ExitCode {
    return switch (err) {
        error.DataRootLocked => .data_root_lock_failure,
        error.RuntimeAssetMissing, error.RuntimeAssetInvalid => .runtime_asset_failure,
        error.AddressInUse, error.AccessDenied, error.BindFailed => .bind_or_startup_failure,
        error.SelfTestFailed => .self_test_failure,
        error.NativeShutdownTimeout => .native_shutdown_timeout,
        else => .configuration_failure,
    };
}

test "static imports stay reachable" {
    try runSelfTest();
}

test "base64url tokens are distinct unpadded 32-byte encodings" {
    const tokens = generateTokens();
    try std.testing.expectEqual(@as(usize, 43), tokens.app_token.len);
    try std.testing.expectEqual(@as(usize, 43), tokens.supervisor_token.len);
    try std.testing.expect(!std.mem.eql(u8, &tokens.app_token, &tokens.supervisor_token));
    try std.testing.expect(std.mem.indexOfScalar(u8, &tokens.app_token, '=') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, &tokens.supervisor_token, '=') == null);
}

test "managed serve requires only CLI flags and rejects external flags" {
    const command = try parseCommand(&.{
        "serve",
        "--runtime",
        "managed",
        "--runtime-root",
        "C:\\runtime",
        "--data-root",
        "C:\\data",
        "--allowed-origin",
        development_origin,
        "--handshake",
        "stdout-v1",
    });
    try std.testing.expect(command == .serve);
    try std.testing.expectEqual(RuntimeMode.managed, command.serve.runtime);

    try std.testing.expectError(error.ManagedModeRejectedExternalFlag, parseServe(&.{
        "--runtime",        "managed",
        "--runtime-root",   "C:\\runtime",
        "--data-root",      "C:\\data",
        "--allowed-origin", development_origin,
        "--handshake",      "stdout-v1",
        "--postgres-host",  "127.0.0.1",
    }));
}

test "external serve requires all database flags and gates non-loopback listen" {
    try std.testing.expectError(error.MissingExternalFlag, parseServe(&.{
        "--runtime",        "external",
        "--runtime-root",   "C:\\runtime",
        "--data-root",      "C:\\data",
        "--allowed-origin", development_origin,
        "--handshake",      "stdout-v1",
    }));

    const config = try parseServe(&.{
        "--runtime",                          "external",
        "--runtime-root",                     "C:\\runtime",
        "--data-root",                        "C:\\data",
        "--allowed-origin",                   development_origin,
        "--handshake",                        "stdout-v1",
        "--development-container",            "--listen",
        "0.0.0.0:7800",                       "--advertised-api-url",
        "http://127.0.0.1:7800",              "--postgres-host",
        "postgresql",                         "--postgres-port",
        "5432",                               "--postgres-database",
        "voyage",                             "--postgres-user",
        "voyage",                             "--postgres-password-file",
        "C:\\secrets\\postgres-password.txt", "--tigerbeetle-address",
        "tigerbeetle:3000",
    });
    try std.testing.expectEqual(RuntimeMode.external, config.runtime);
    try std.testing.expect(config.external != null);
}

test "origin and advertised API URL validation is exact" {
    try std.testing.expect(isAllowedOrigin(packaged_origin));
    try std.testing.expect(isAllowedOrigin(development_origin));
    try std.testing.expect(!isAllowedOrigin("http://localhost:1421"));
    try std.testing.expect(isValidApiUrl("http://127.0.0.1:7800"));
    try std.testing.expect(!isValidApiUrl("https://127.0.0.1:7800"));
    try std.testing.expect(!isValidApiUrl("http://user@127.0.0.1:7800"));
    try std.testing.expect(!isValidApiUrl("http://127.0.0.1:7800/path"));
}

comptime {
    if (builtin.os.tag != .windows) {
        @compileLog("Voyage VII v2 API-001 current native gate is Windows 11 x64 only.");
    }
}
