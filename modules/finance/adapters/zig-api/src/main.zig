const std = @import("std");
const api = @import("api");

pub const sqlite_adapter = @import("sqlite/root.zig");
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
};

pub const Command = union(enum) {
    serve: ServeConfig,
    self_test,
    version,
};

pub const ExternalDatabaseConfig = struct {
    sqlite_path: []const u8,
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
    var sqlite_path: ?[]const u8 = null;
    var tigerbeetle_address: ?[]const u8 = null;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
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
        } else if (std.mem.eql(u8, flag, "--sqlite-path")) {
            if (sqlite_path != null) return error.DuplicateFlag;
            if (!std.fs.path.isAbsolute(value)) return error.PathMustBeAbsolute;
            sqlite_path = value;
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
        .external = null,
    };

    if (!isLoopbackListen(listen.host)) {
        return error.InvalidListen;
    }

    const any_external = sqlite_path != null or tigerbeetle_address != null;
    if (mode == .managed) {
        if (any_external) return error.ManagedModeRejectedExternalFlag;
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
        .external = .{
            .sqlite_path = sqlite_path orelse return error.MissingExternalFlag,
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

    var runtime = runtime_supervisor.ManagedRuntime.init(allocator, .{
        .runtime_root = config.runtime_root,
        .data_root = config.data_root,
    });
    defer runtime.deinit();
    if (config.runtime == .managed) {
        try runtime.startAsync();
    } else {
        const external = config.external orelse return error.MissingExternalFlag;
        try runtime.startExternalAsync(.{
            .sqlite_path = external.sqlite_path,
            .tigerbeetle_address = external.tigerbeetle_address,
        });
    }

    const http_config = http.Config{
        .allowed_origin = config.allowed_origin,
        .app_token = &tokens.app_token,
        .supervisor_token = &tokens.supervisor_token,
    };

    while (true) {
        var connection = server.accept() catch |err| {
            std.debug.print("api_accept=failed error={s}\n", .{@errorName(err)});
            continue;
        };
        const should_shutdown = handleHttpConnection(allocator, connection.stream, http_config, &runtime) catch |err| {
            std.debug.print("api_connection=failed error={s}\n", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
        connection.stream.close();
        if (should_shutdown) {
            runtime.shutdown();
            return;
        }
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

fn handleHttpConnection(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    config: http.Config,
    runtime: *runtime_supervisor.ManagedRuntime,
) !bool {
    var buffer: [72 * 1024]u8 = undefined;
    const read_len = try std.posix.recv(stream.handle, &buffer, 0);
    if (read_len == 0) return false;

    const request = parseHttpRequest(buffer[0..read_len]) catch {
        try stream.writeAll("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return false;
    };

    const previous_snapshot = runtime.snapshot();
    var snapshot = previous_snapshot;
    var response = try http.handle(allocator, config, &snapshot, request);
    defer response.deinit(allocator);
    const actions = runtime.mergeHttpSnapshotAndPlan(previous_snapshot, snapshot);

    try writeHttpResponse(stream, response);
    if (actions.retry_sqlite) runtime.runRetry(.sqlite);
    if (actions.retry_tigerbeetle) runtime.runRetry(.tigerbeetle);
    return actions.shutdown;
}

fn parseHttpRequest(bytes: []const u8) !http.Request {
    const header_end = std.mem.indexOf(u8, bytes, "\r\n\r\n") orelse return error.InvalidRequest;
    const head = bytes[0..header_end];
    const body = bytes[header_end + 4 ..];

    var lines = std.mem.splitSequence(u8, head, "\r\n");
    const request_line = lines.next() orelse return error.InvalidRequest;
    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method_text = parts.next() orelse return error.InvalidRequest;
    const path = parts.next() orelse return error.InvalidRequest;
    _ = parts.next() orelse return error.InvalidRequest;

    var origin: ?[]const u8 = null;
    var authorization: ?[]const u8 = null;
    var request_id: ?[]const u8 = null;
    var content_length: usize = 0;
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "Origin")) {
            origin = value;
        } else if (std.ascii.eqlIgnoreCase(name, "Authorization")) {
            authorization = value;
        } else if (std.ascii.eqlIgnoreCase(name, "X-Request-Id")) {
            request_id = value;
        } else if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            content_length = try std.fmt.parseInt(usize, value, 10);
        }
    }
    if (content_length > body.len) return error.InvalidRequest;

    return .{
        .method = parseHttpMethod(method_text) orelse return error.InvalidRequest,
        .path = path,
        .body = body[0..content_length],
        .origin = origin,
        .authorization = authorization,
        .request_id = request_id,
    };
}

fn parseHttpMethod(value: []const u8) ?http.Method {
    if (std.mem.eql(u8, value, "GET")) return .GET;
    if (std.mem.eql(u8, value, "POST")) return .POST;
    if (std.mem.eql(u8, value, "OPTIONS")) return .OPTIONS;
    if (std.mem.eql(u8, value, "PUT")) return .PUT;
    if (std.mem.eql(u8, value, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, value, "PATCH")) return .PATCH;
    return null;
}

fn writeHttpResponse(stream: std.net.Stream, response: http.Response) !void {
    var header: [1024]u8 = undefined;
    const reason = reasonPhrase(response.status_code);
    const cors = response.allow_origin != null;
    const head = if (cors)
        try std.fmt.bufPrint(
            &header,
            "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\nX-Request-Id: {s}\r\nAccess-Control-Allow-Origin: {s}\r\nAccess-Control-Allow-Methods: {s}\r\nAccess-Control-Allow-Headers: {s}\r\n\r\n",
            .{ response.status_code, reason, response.body.len, response.request_id, response.allow_origin.?, response.allow_methods orelse "GET, POST, OPTIONS", response.allow_headers orelse "Authorization, Accept, Content-Type, X-Request-Id" },
        )
    else
        try std.fmt.bufPrint(
            &header,
            "HTTP/1.1 {d} {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\nX-Request-Id: {s}\r\n\r\n",
            .{ response.status_code, reason, response.body.len, response.request_id },
        );
    try stream.writeAll(head);
    try stream.writeAll(response.body);
}

fn reasonPhrase(code: u16) []const u8 {
    return switch (code) {
        200 => "OK",
        202 => "Accepted",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        409 => "Conflict",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        else => "OK",
    };
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
    try sqlite_adapter.selfTest();
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
        "--sqlite-path",    "C:\\data\\voyage-vii.sqlite3",
    }));
}

test "external serve requires all database flags and rejects non-loopback listen" {
    try std.testing.expectError(error.MissingExternalFlag, parseServe(&.{
        "--runtime",        "external",
        "--runtime-root",   "C:\\runtime",
        "--data-root",      "C:\\data",
        "--allowed-origin", development_origin,
        "--handshake",      "stdout-v1",
    }));

    try std.testing.expectError(error.InvalidListen, parseServe(&.{
        "--runtime",                    "external",
        "--runtime-root",               "C:\\runtime",
        "--data-root",                  "C:\\data",
        "--allowed-origin",             development_origin,
        "--handshake",                  "stdout-v1",
        "--listen",                     "0.0.0.0:7800",
        "--advertised-api-url",
        "http://127.0.0.1:7800",        "--sqlite-path",
        "C:\\data\\voyage-vii.sqlite3", "--tigerbeetle-address",
        "tigerbeetle:3000",
    }));

    const config = try parseServe(&.{
        "--runtime",                    "external",
        "--runtime-root",               "C:\\runtime",
        "--data-root",                  "C:\\data",
        "--allowed-origin",             development_origin,
        "--handshake",                  "stdout-v1",
        "--sqlite-path",                "C:\\data\\voyage-vii.sqlite3",
        "--tigerbeetle-address",        "127.0.0.1:3000",
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
