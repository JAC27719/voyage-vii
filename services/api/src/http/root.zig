const std = @import("std");
const status = @import("../status/root.zig");

pub const max_body_bytes = 64 * 1024;

pub const Method = enum {
    GET,
    POST,
    OPTIONS,
    PUT,
    DELETE,
    PATCH,
};

pub const Scope = enum {
    none,
    app,
    supervisor,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    body: []const u8 = "",
    origin: ?[]const u8 = null,
    authorization: ?[]const u8 = null,
    request_id: ?[]const u8 = null,
};

pub const Config = struct {
    allowed_origin: []const u8,
    app_token: []const u8,
    supervisor_token: []const u8,
};

pub const Response = struct {
    status_code: u16,
    body: []u8,
    request_id: []u8,
    allow_origin: ?[]u8 = null,
    allow_methods: ?[]const u8 = null,

    pub fn deinit(self: Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        allocator.free(self.request_id);
        if (self.allow_origin) |origin| allocator.free(origin);
    }
};

pub fn handle(
    allocator: std.mem.Allocator,
    config: Config,
    snapshot: *status.Snapshot,
    request: Request,
) !Response {
    const request_id = try allocator.dupe(u8, request.request_id orelse "req-generated");
    errdefer allocator.free(request_id);

    if (request.origin) |origin| {
        if (!std.mem.eql(u8, origin, config.allowed_origin)) {
            return errorResponse(allocator, request_id, .origin_not_allowed, null);
        }
    }
    if (request.body.len > max_body_bytes) {
        return errorResponse(allocator, request_id, .body_too_large, null);
    }

    const route = classifyRoute(request.path);
    if (request.method == .OPTIONS) {
        if (route == .unknown or route == .retry_component_unknown) {
            return errorResponse(allocator, request_id, .not_found, null);
        }
        return emptyResponse(allocator, request_id, 204, request.origin);
    }

    const required = requiredScope(route);
    if (required != .none) {
        authorize(config, request.authorization, required) catch |err| switch (err) {
            error.Unauthorized => return errorResponse(allocator, request_id, .unauthorized, request.origin),
            error.Forbidden => return errorResponse(allocator, request_id, .forbidden, request.origin),
        };
    }
    if (expectedMethod(route)) |expected| {
        if (request.method != expected) return errorResponse(allocator, request_id, .method_not_allowed, request.origin);
    }

    return switch (route) {
        .live => jsonResponse(allocator, request_id, 200, "{\"status\":\"live\"}", request.origin),
        .ready => readyResponse(allocator, request_id, snapshot.*, request.origin),
        .status => statusResponse(allocator, request_id, snapshot.*, request.origin),
        .retry_sqlite => retryResponse(allocator, request_id, snapshot, &.{.sqlite}, request.origin),
        .retry_tigerbeetle => retryResponse(allocator, request_id, snapshot, &.{.tigerbeetle}, request.origin),
        .retry_component_unknown => errorResponse(allocator, request_id, .component_not_found, request.origin),
        .retry_all => retryResponse(allocator, request_id, snapshot, &.{ .sqlite, .tigerbeetle }, request.origin),
        .shutdown => shutdownResponse(allocator, request_id, snapshot, request.origin),
        .known_wrong_method => errorResponse(allocator, request_id, .method_not_allowed, request.origin),
        .unknown => errorResponse(allocator, request_id, .not_found, request.origin),
    };
}

const Route = enum {
    live,
    ready,
    status,
    retry_sqlite,
    retry_tigerbeetle,
    retry_component_unknown,
    retry_all,
    shutdown,
    known_wrong_method,
    unknown,
};

fn classifyRoute(path: []const u8) Route {
    if (std.mem.eql(u8, path, "/health/live")) return .live;
    if (std.mem.eql(u8, path, "/health/ready")) return .ready;
    if (std.mem.eql(u8, path, "/api/v1/system/status")) return .status;
    if (std.mem.eql(u8, path, "/api/v1/system/retry")) return .retry_all;
    if (std.mem.eql(u8, path, "/api/v1/system/shutdown")) return .shutdown;

    const prefix = "/api/v1/system/components/";
    const suffix = "/retry";
    if (std.mem.startsWith(u8, path, prefix) and std.mem.endsWith(u8, path, suffix)) {
        const component = path[prefix.len .. path.len - suffix.len];
        if (std.mem.eql(u8, component, "sqlite")) return .retry_sqlite;
        if (std.mem.eql(u8, component, "tigerbeetle")) return .retry_tigerbeetle;
        return .retry_component_unknown;
    }
    return .unknown;
}

fn requiredScope(route: Route) Scope {
    return switch (route) {
        .status, .retry_sqlite, .retry_tigerbeetle, .retry_component_unknown, .retry_all => .app,
        .shutdown => .supervisor,
        else => .none,
    };
}

fn expectedMethod(route: Route) ?Method {
    return switch (route) {
        .live, .ready, .status => .GET,
        .retry_sqlite, .retry_tigerbeetle, .retry_component_unknown, .retry_all, .shutdown => .POST,
        .known_wrong_method, .unknown => null,
    };
}

fn authorize(config: Config, authorization: ?[]const u8, required: Scope) !void {
    const value = authorization orelse return error.Unauthorized;
    const prefix = "Bearer ";
    if (!std.mem.startsWith(u8, value, prefix)) return error.Unauthorized;
    const token = value[prefix.len..];
    const app_match = constantTimeEqual(token, config.app_token);
    const supervisor_match = constantTimeEqual(token, config.supervisor_token);
    return switch (required) {
        .none => {},
        .app => if (app_match) {} else if (supervisor_match) error.Forbidden else error.Unauthorized,
        .supervisor => if (supervisor_match) {} else if (app_match) error.Forbidden else error.Unauthorized,
    };
}

pub fn constantTimeEqual(left: []const u8, right: []const u8) bool {
    var diff: usize = left.len ^ right.len;
    const max_len = @max(left.len, right.len);
    for (0..max_len) |index| {
        const a: u8 = if (index < left.len) left[index] else 0;
        const b: u8 = if (index < right.len) right[index] else 0;
        diff |= @as(usize, a ^ b);
    }
    return diff == 0;
}

fn readyResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    snapshot: status.Snapshot,
    origin: ?[]const u8,
) !Response {
    if (snapshot.isReady()) {
        return jsonResponse(allocator, request_id, 200, "{\"status\":\"ready\"}", origin);
    }
    return jsonResponse(allocator, request_id, 503, "{\"status\":\"notReady\"}", origin);
}

fn statusResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    snapshot: status.Snapshot,
    origin: ?[]const u8,
) !Response {
    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"schemaVersion\":1,\"requestId\":");
    try appendJsonString(allocator, &body, request_id);
    try body.writer(allocator).print(",\"overallState\":\"{s}\",\"components\":[", .{snapshot.overall_state.json()});
    try appendComponent(allocator, &body, snapshot.sqlite);
    try body.appendSlice(allocator, ",");
    try appendComponent(allocator, &body, snapshot.tigerbeetle);
    try body.appendSlice(allocator, "]}");
    return responseWithOwnedBody(allocator, request_id, 200, try body.toOwnedSlice(allocator), origin);
}

fn appendComponent(allocator: std.mem.Allocator, body: *std.ArrayList(u8), component: status.ComponentStatus) !void {
    try body.writer(allocator).print(
        "{{\"id\":\"{s}\",\"displayName\":\"{s}\",\"version\":\"{s}\",\"state\":\"{s}\",\"lastCheckedAt\":",
        .{ component.id.json(), component.id.displayName(), component.id.version(), component.state.json() },
    );
    if (component.last_checked_at) |value| {
        try appendJsonString(allocator, body, value);
    } else {
        try body.appendSlice(allocator, "null");
    }
    try body.writer(allocator).print(",\"attemptCount\":{d},\"error\":", .{component.attempt_count});
    if (component.diagnostic) |err| {
        try body.writer(allocator).print("{{\"code\":\"{s}\",\"message\":", .{err.code.json()});
        try appendJsonString(allocator, body, err.message);
        try body.appendSlice(allocator, "}");
    } else {
        try body.appendSlice(allocator, "null");
    }
    try body.appendSlice(allocator, "}");
}

fn retryResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    snapshot: *status.Snapshot,
    targets: []const status.ComponentId,
    origin: ?[]const u8,
) !Response {
    var accepted = false;
    for (targets) |target| {
        accepted = snapshot.markRetry(target) or accepted;
    }

    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"requestId\":");
    try appendJsonString(allocator, &body, request_id);
    try body.writer(allocator).print(",\"accepted\":{s},\"targets\":[", .{if (accepted) "true" else "false"});
    for (targets, 0..) |target, index| {
        if (index != 0) try body.appendSlice(allocator, ",");
        try body.writer(allocator).print("\"{s}\"", .{target.json()});
    }
    try body.appendSlice(allocator, "]}");
    return responseWithOwnedBody(allocator, request_id, 202, try body.toOwnedSlice(allocator), origin);
}

fn shutdownResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    snapshot: *status.Snapshot,
    origin: ?[]const u8,
) !Response {
    if (!snapshot.markStopping()) return errorResponse(allocator, request_id, .shutting_down, origin);
    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"requestId\":");
    try appendJsonString(allocator, &body, request_id);
    try body.appendSlice(allocator, ",\"accepted\":true}");
    return responseWithOwnedBody(allocator, request_id, 202, try body.toOwnedSlice(allocator), origin);
}

fn emptyResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    status_code: u16,
    origin: ?[]const u8,
) !Response {
    return responseWithOwnedBody(allocator, request_id, status_code, try allocator.dupe(u8, ""), origin);
}

fn jsonResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    status_code: u16,
    body: []const u8,
    origin: ?[]const u8,
) !Response {
    return responseWithOwnedBody(allocator, request_id, status_code, try allocator.dupe(u8, body), origin);
}

fn errorResponse(
    allocator: std.mem.Allocator,
    request_id: []u8,
    code: status.ErrorCode,
    origin: ?[]const u8,
) !Response {
    var body = std.ArrayList(u8){};
    errdefer body.deinit(allocator);
    try body.writer(allocator).print("{{\"error\":{{\"code\":\"{s}\",\"message\":", .{code.json()});
    try appendJsonString(allocator, &body, status.messageFor(code));
    try body.appendSlice(allocator, ",\"requestId\":");
    try appendJsonString(allocator, &body, request_id);
    try body.appendSlice(allocator, "}}}");
    return responseWithOwnedBody(allocator, request_id, statusForError(code), try body.toOwnedSlice(allocator), origin);
}

fn appendJsonString(allocator: std.mem.Allocator, body: *std.ArrayList(u8), value: []const u8) !void {
    try body.append(allocator, '"');
    for (value) |byte| {
        if (byte == '\n') {
            try body.appendSlice(allocator, "\\n");
            continue;
        }
        if (byte == '\r') {
            try body.appendSlice(allocator, "\\r");
            continue;
        }
        if (byte == '\t') {
            try body.appendSlice(allocator, "\\t");
            continue;
        }
        switch (byte) {
            '"' => try body.appendSlice(allocator, "\\\""),
            '\\' => try body.appendSlice(allocator, "\\\\"),
            0x00...0x1f => try body.writer(allocator).print("\\u{x:0>4}", .{byte}),
            else => try body.append(allocator, byte),
        }
    }
    try body.append(allocator, '"');
}

fn responseWithOwnedBody(
    allocator: std.mem.Allocator,
    request_id: []u8,
    status_code: u16,
    body: []u8,
    origin: ?[]const u8,
) !Response {
    return .{
        .status_code = status_code,
        .body = body,
        .request_id = request_id,
        .allow_origin = if (origin) |value| try allocator.dupe(u8, value) else null,
        .allow_methods = "GET, POST, OPTIONS",
    };
}

fn statusForError(code: status.ErrorCode) u16 {
    return switch (code) {
        .invalid_request => 400,
        .body_too_large => 413,
        .unauthorized => 401,
        .forbidden, .origin_not_allowed => 403,
        .not_found, .component_not_found => 404,
        .method_not_allowed => 405,
        .retry_not_allowed, .data_root_locked => 409,
        .internal_error => 500,
        .service_unavailable,
        .shutting_down,
        .sqlite_unavailable,
        .sqlite_busy,
        .sqlite_timeout,
        .tigerbeetle_unavailable,
        .tigerbeetle_timeout,
        .native_shutdown_timeout,
        .runtime_asset_missing,
        .runtime_asset_invalid,
        => 503,
    };
}

pub fn selfTest() !void {
    var snapshot = status.Snapshot.init();
    const config = Config{
        .allowed_origin = "http://localhost:1420",
        .app_token = "app-token",
        .supervisor_token = "supervisor-token",
    };
    var response = try handle(std.heap.page_allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/health/live",
        .request_id = "self-test",
    });
    defer response.deinit(std.heap.page_allocator);
    if (response.status_code != 200) return error.InvalidHttpStatus;
    if (!std.mem.eql(u8, response.body, "{\"status\":\"live\"}")) return error.InvalidHttpBody;
}

test "API-004 unauthenticated health and readiness bodies are exact" {
    var snapshot = status.Snapshot.init();
    const config = testConfig();

    var live = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/health/live",
        .request_id = "req-live",
    });
    defer live.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), live.status_code);
    try std.testing.expectEqualStrings("req-live", live.request_id);
    try std.testing.expectEqualStrings("{\"status\":\"live\"}", live.body);

    var not_ready = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/health/ready",
        .request_id = "req-ready",
    });
    defer not_ready.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 503), not_ready.status_code);
    try std.testing.expectEqualStrings("{\"status\":\"notReady\"}", not_ready.body);

    snapshot.overall_state = .ready;
    snapshot.sqlite.state = .healthy;
    snapshot.tigerbeetle.state = .healthy;
    var ready = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/health/ready",
        .request_id = "req-ready",
    });
    defer ready.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), ready.status_code);
    try std.testing.expectEqualStrings("{\"status\":\"ready\"}", ready.body);
}

test "API-004 authentication scopes are disjoint" {
    var snapshot = status.Snapshot.init();
    const config = testConfig();

    var missing = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/api/v1/system/status",
        .request_id = "req-auth",
    });
    defer missing.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 401), missing.status_code);
    try std.testing.expect(std.mem.indexOf(u8, missing.body, "\"code\":\"unauthorized\"") != null);

    var wrong_scope = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/api/v1/system/status",
        .authorization = "Bearer supervisor-token",
        .request_id = "req-auth",
    });
    defer wrong_scope.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 403), wrong_scope.status_code);
    try std.testing.expect(std.mem.indexOf(u8, wrong_scope.body, "\"code\":\"forbidden\"") != null);

    var ok = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/api/v1/system/status",
        .authorization = "Bearer app-token",
        .request_id = "req-auth",
    });
    defer ok.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 200), ok.status_code);
    try std.testing.expect(std.mem.indexOf(u8, ok.body, "\"schemaVersion\":1") != null);
}

test "API-004 CORS preflight body limit route and request id behavior" {
    var snapshot = status.Snapshot.init();
    const config = testConfig();

    var preflight = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .OPTIONS,
        .path = "/api/v1/system/status",
        .origin = "http://localhost:1420",
        .request_id = "req-cors",
    });
    defer preflight.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 204), preflight.status_code);
    try std.testing.expectEqualStrings("", preflight.body);
    try std.testing.expectEqualStrings("http://localhost:1420", preflight.allow_origin.?);

    var unknown_preflight = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .OPTIONS,
        .path = "/api/v1/system/components/postgres/retry",
        .origin = "http://localhost:1420",
        .request_id = "req-cors",
    });
    defer unknown_preflight.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 404), unknown_preflight.status_code);

    var bad_origin = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/health/live",
        .origin = "http://localhost:1421",
        .request_id = "req-cors",
    });
    defer bad_origin.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 403), bad_origin.status_code);
    try std.testing.expect(std.mem.indexOf(u8, bad_origin.body, "\"code\":\"origin_not_allowed\"") != null);

    const large = try std.testing.allocator.alloc(u8, max_body_bytes + 1);
    defer std.testing.allocator.free(large);
    var too_large = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/retry",
        .authorization = "Bearer app-token",
        .body = large,
        .request_id = "req-large",
    });
    defer too_large.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 413), too_large.status_code);
    try std.testing.expectEqualStrings("req-large", too_large.request_id);
}

test "API-004 retry is idempotent and ordered" {
    var snapshot = status.Snapshot.init();
    snapshot.sqlite.state = .unhealthy;
    snapshot.tigerbeetle.state = .healthy;
    const config = testConfig();

    var retry_all = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/retry",
        .authorization = "Bearer app-token",
        .request_id = "req-retry",
    });
    defer retry_all.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 202), retry_all.status_code);
    try std.testing.expectEqualStrings(
        "{\"requestId\":\"req-retry\",\"accepted\":true,\"targets\":[\"sqlite\",\"tigerbeetle\"]}",
        retry_all.body,
    );
    try std.testing.expectEqual(status.ComponentState.retrying, snapshot.sqlite.state);
    try std.testing.expectEqual(status.ComponentState.healthy, snapshot.tigerbeetle.state);

    var duplicate = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/components/sqlite/retry",
        .authorization = "Bearer app-token",
        .request_id = "req-retry-2",
    });
    defer duplicate.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 202), duplicate.status_code);
    try std.testing.expectEqualStrings(
        "{\"requestId\":\"req-retry-2\",\"accepted\":false,\"targets\":[\"sqlite\"]}",
        duplicate.body,
    );
}

test "API-004 shutdown is supervisor only and quiesces duplicates" {
    var snapshot = status.Snapshot.init();
    const config = testConfig();

    var app_denied = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/shutdown",
        .authorization = "Bearer app-token",
        .request_id = "req-stop",
    });
    defer app_denied.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 403), app_denied.status_code);

    var accepted = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/shutdown",
        .authorization = "Bearer supervisor-token",
        .request_id = "req-stop",
    });
    defer accepted.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 202), accepted.status_code);
    try std.testing.expectEqualStrings("{\"requestId\":\"req-stop\",\"accepted\":true}", accepted.body);

    var retry_after_shutdown = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/retry",
        .authorization = "Bearer app-token",
        .request_id = "req-retry-stop",
    });
    defer retry_after_shutdown.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 202), retry_after_shutdown.status_code);
    try std.testing.expectEqualStrings(
        "{\"requestId\":\"req-retry-stop\",\"accepted\":false,\"targets\":[\"sqlite\",\"tigerbeetle\"]}",
        retry_after_shutdown.body,
    );
    try std.testing.expectEqual(status.OverallState.stopping, snapshot.overall_state);

    var duplicate = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .POST,
        .path = "/api/v1/system/shutdown",
        .authorization = "Bearer supervisor-token",
        .request_id = "req-stop-2",
    });
    defer duplicate.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 503), duplicate.status_code);
    try std.testing.expect(std.mem.indexOf(u8, duplicate.body, "\"code\":\"shutting_down\"") != null);
}

test "API-004 request ids and diagnostic strings are JSON escaped" {
    var snapshot = status.Snapshot.init();
    snapshot.sqlite.diagnostic = .{ .code = .sqlite_unavailable, .message = "quoted \"slash\\ text" };
    const config = testConfig();

    var response = try handle(std.testing.allocator, config, &snapshot, .{
        .method = .GET,
        .path = "/api/v1/system/status",
        .authorization = "Bearer app-token",
        .request_id = "req\"\\id",
    });
    defer response.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "req\\\"\\\\id") != null);
    try std.testing.expect(std.mem.indexOf(u8, response.body, "quoted \\\"slash\\\\ text") != null);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, response.body, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .object);
}

fn testConfig() Config {
    return .{
        .allowed_origin = "http://localhost:1420",
        .app_token = "app-token",
        .supervisor_token = "supervisor-token",
    };
}
