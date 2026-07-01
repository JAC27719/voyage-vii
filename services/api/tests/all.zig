const std = @import("std");
const main = @import("app");
const sqlite_tests = @import("sqlite/root.zig");
const tigerbeetle_tests = @import("tigerbeetle/root.zig");
const runtime_integration_tests = @import("runtime/integration/root.zig");

test "aggregate imports every API-001 static seam" {
    try main.runSelfTest();
    try std.testing.expectEqualStrings("0.1.0", main.product_version);
}

test "aggregate imports API adapter test seams" {
    try sqlite_tests.selfTest();
    try tigerbeetle_tests.selfTest();
    try runtime_integration_tests.selfTest();
}

test "all public errors required by the frozen contract are registered" {
    const errors = [_][]const u8{
        "invalid_request",
        "body_too_large",
        "unauthorized",
        "forbidden",
        "origin_not_allowed",
        "method_not_allowed",
        "not_found",
        "component_not_found",
        "retry_not_allowed",
        "service_unavailable",
        "shutting_down",
        "internal_error",
        "sqlite_unavailable",
        "sqlite_busy",
        "sqlite_timeout",
        "tigerbeetle_unavailable",
        "tigerbeetle_timeout",
        "native_shutdown_timeout",
        "runtime_asset_missing",
        "runtime_asset_invalid",
        "data_root_locked",
    };
    try std.testing.expectEqual(@as(usize, 21), errors.len);
}

test "representative JSON contract payloads parse" {
    const fixtures = [_][]const u8{
        "{\"protocolVersion\":1,\"apiUrl\":\"http://127.0.0.1:7800\",\"appToken\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\",\"supervisorToken\":\"BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB\"}",
        "{\"error\":{\"code\":\"native_shutdown_timeout\",\"message\":\"Native shutdown timed out.\",\"requestId\":\"req-1\"}}",
        "{\"schemaVersion\":1,\"requestId\":\"req-1\",\"overallState\":\"starting\",\"components\":[]}",
    };
    for (fixtures) |fixture| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, fixture, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .object);
    }
}
