const std = @import("std");
const native_inputs = @import("native_inputs");

const tb = if (native_inputs.tigerbeetle_client_enabled) @cImport({
    @cInclude("tb_client.h");
}) else struct {
    pub const tb_client_t = void;
    pub const tb_packet_t = extern struct {};
    pub const tb_uint128_t = u128;
    pub const TB_INIT_SUCCESS = 0;
    pub const TB_CLIENT_OK = 0;
    pub const TB_PACKET_OK = 0;
    pub const TB_PACKET_CLIENT_SHUTDOWN = 5;
    pub const TB_OPERATION_LOOKUP_ACCOUNTS = 140;
};

pub const component_id = "tigerbeetle";
pub const request_timeout_ms: u32 = 5_000;
pub const shutdown_watchdog_ms: u32 = 10_000;
pub const stalled_deinit_parent_limit_ms: u32 = 12_000;
pub const native_shutdown_timeout_exit_code: u8 = 7;
pub const native_enabled = native_inputs.tigerbeetle_client_enabled;

pub const ErrorCode = enum {
    tigerbeetle_unavailable,
    tigerbeetle_timeout,
    native_shutdown_timeout,
    internal_error,
};

pub const Config = struct {
    address: []const u8,
    cluster_id: [16]u8 = [_]u8{0} ** 16,
};

pub const SanitizedDiagnostic = struct {
    operation: []const u8,
    elapsed_ms: u64,
};

pub const ProbeResult = struct {
    result_size: u32,
    callback_count: u32,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex = .{},
    native: tb.tb_client_t = undefined,
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator, config: Config) !*Client {
        if (!native_enabled) return error.NativeClientDisabled;
        try validateAddress(config.address);

        const client = try allocator.create(Client);
        errdefer allocator.destroy(client);
        client.* = .{ .allocator = allocator };

        const status = tb.tb_client_init(
            &client.native,
            &config.cluster_id,
            config.address.ptr,
            @intCast(config.address.len),
            @intFromPtr(client),
            onCompletion,
        );
        if (status != tb.TB_INIT_SUCCESS) return error.ClientInitFailed;
        return client;
    }

    pub fn deinit(self: *Client) !void {
        if (!native_enabled) return;
        self.mutex.lock();
        if (!self.closed) {
            deinitWithWatchdog(&self.native, realDeinitThread) catch |err| {
                self.mutex.unlock();
                return err;
            };
            self.closed = true;
        }
        self.mutex.unlock();
        const allocator = self.allocator;
        allocator.destroy(self);
    }

    pub fn healthProbe(self: *Client) !ProbeResult {
        if (!native_enabled) return error.NativeClientDisabled;
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.closed) return error.ClientClosed;

        var completion = Completion{ .client = self };
        var ids = [_]tb.tb_uint128_t{0};
        var packet: tb.tb_packet_t = std.mem.zeroes(tb.tb_packet_t);
        packet.user_data = @ptrCast(&completion);
        packet.data = @ptrCast(&ids);
        packet.data_size = @sizeOf(@TypeOf(ids));
        packet.operation = @intCast(tb.TB_OPERATION_LOOKUP_ACCOUNTS);
        packet.status = @intCast(tb.TB_PACKET_OK);

        const submit_status = tb.tb_client_submit(&self.native, &packet);
        if (submit_status != tb.TB_CLIENT_OK) return error.ClientSubmitFailed;

        const wait_result = waitForCompletion(&completion, timeoutNs(request_timeout_ms));
        if (!wait_result.completed) {
            try self.deinitLocked();
            try verifyCallback(&completion);
            if (completion.packet_status != tb.TB_PACKET_CLIENT_SHUTDOWN) return error.ShutdownDidNotCancelPacket;
            return error.RequestTimeout;
        }

        try verifyCallback(&completion);
        if (completion.packet_status != tb.TB_PACKET_OK) return error.PacketFailed;
        return .{
            .result_size = completion.result_size,
            .callback_count = completion.callback_count,
        };
    }

    fn deinitLocked(self: *Client) !void {
        if (!self.closed) {
            try deinitWithWatchdog(&self.native, realDeinitThread);
            self.closed = true;
        }
    }
};

const Completion = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    client: *Client,
    completed: bool = false,
    callback_count: u32 = 0,
    packet_status: u8 = 0,
    result_size: u32 = 0,
    context_matches: bool = false,
};

const Shutdown = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    completed: bool = false,
    status: i32 = -1,

    fn complete(self: *Shutdown, status: i32) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.status = status;
        self.completed = true;
        self.condition.signal();
    }
};

const WaitResult = struct {
    completed: bool,
    elapsed_ns: u64,
};

fn validateAddress(address: []const u8) !void {
    if (address.len == 0) return error.InvalidAddress;
    if (address.len > std.math.maxInt(u32)) return error.InvalidAddress;
    if (std.mem.indexOfAny(u8, address, " \t\r\n") != null) return error.InvalidAddress;
}

fn waitForCompletion(completion: *Completion, timeout_ns: u64) WaitResult {
    var timer = std.time.Timer.start() catch unreachable;
    completion.mutex.lock();
    defer completion.mutex.unlock();

    while (!completion.completed) {
        const elapsed_ns = timer.read();
        if (elapsed_ns >= timeout_ns) return .{ .completed = false, .elapsed_ns = elapsed_ns };
        completion.condition.timedWait(&completion.mutex, timeout_ns - elapsed_ns) catch |err| switch (err) {
            error.Timeout => return .{ .completed = completion.completed, .elapsed_ns = timer.read() },
        };
    }
    return .{ .completed = true, .elapsed_ns = timer.read() };
}

fn verifyCallback(completion: *Completion) !void {
    completion.mutex.lock();
    defer completion.mutex.unlock();
    if (!completion.completed) return error.CallbackMissing;
    if (completion.callback_count != 1) return error.CallbackCountInvalid;
    if (!completion.context_matches) return error.CallbackContextInvalid;
}

fn onCompletion(
    context_value: usize,
    packet: [*c]tb.tb_packet_t,
    timestamp: u64,
    result: [*c]const u8,
    result_size: u32,
) callconv(.c) void {
    _ = timestamp;
    _ = result;

    const completion: *Completion = @ptrCast(@alignCast(packet.*.user_data.?));
    completion.mutex.lock();
    defer completion.mutex.unlock();

    completion.callback_count += 1;
    completion.packet_status = packet.*.status;
    completion.result_size = result_size;
    completion.context_matches =
        context_value == @intFromPtr(completion.client) and
        packet.*.user_data == @as(?*anyopaque, @ptrCast(completion));
    completion.completed = true;
    completion.condition.signal();
}

fn deinitWithWatchdog(
    native: *tb.tb_client_t,
    comptime deinit_thread: fn (*Shutdown, *tb.tb_client_t) void,
) !void {
    var shutdown = Shutdown{};
    var thread = try std.Thread.spawn(.{}, deinit_thread, .{ &shutdown, native });
    try waitForShutdown(&shutdown, &thread);
}

fn realDeinitThread(shutdown: *Shutdown, native: *tb.tb_client_t) void {
    shutdown.complete(@intCast(tb.tb_client_deinit(native)));
}

fn waitForShutdown(shutdown: *Shutdown, thread: *std.Thread) !void {
    var timer = std.time.Timer.start() catch unreachable;
    var status: i32 = undefined;

    shutdown.mutex.lock();
    while (!shutdown.completed) {
        const elapsed_ns = timer.read();
        if (elapsed_ns >= timeoutNs(shutdown_watchdog_ms)) {
            shutdown.mutex.unlock();
            std.process.exit(native_shutdown_timeout_exit_code);
        }
        shutdown.condition.timedWait(
            &shutdown.mutex,
            timeoutNs(shutdown_watchdog_ms) - elapsed_ns,
        ) catch |err| switch (err) {
            error.Timeout => {},
        };
    }
    status = shutdown.status;
    shutdown.mutex.unlock();

    thread.join();
    if (status != tb.TB_CLIENT_OK) return error.ClientDeinitFailed;
    if (timer.read() >= timeoutNs(shutdown_watchdog_ms)) return error.ClientDeinitTooSlow;
}

fn timeoutNs(milliseconds: u32) u64 {
    return @as(u64, milliseconds) * std.time.ns_per_ms;
}

pub fn mapNativeError(err: anyerror) ErrorCode {
    return switch (err) {
        error.RequestTimeout, error.ClientDeinitTooSlow => .tigerbeetle_timeout,
        error.ClientInitFailed, error.ClientSubmitFailed, error.PacketFailed, error.ShutdownDidNotCancelPacket => .tigerbeetle_unavailable,
        error.NativeShutdownTimeout => .native_shutdown_timeout,
        else => .internal_error,
    };
}

pub fn sanitizedDiagnostic(operation: []const u8, elapsed_ms: u64) SanitizedDiagnostic {
    return .{ .operation = operation, .elapsed_ms = elapsed_ms };
}

pub fn containsSecretLikeText(message: []const u8) bool {
    const needles = [_][]const u8{
        "secret",
        "credential",
        "authorization",
        "token",
        "account_id=",
        "transfer_id=",
        "debit_account_id",
        "credit_account_id",
        "amount=",
    };
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(message, needle) != null) return true;
    }
    return false;
}

pub fn selfTest() !void {
    if (request_timeout_ms != 5_000) return error.InvalidTigerBeetleConfiguration;
    if (shutdown_watchdog_ms != 10_000) return error.InvalidTigerBeetleConfiguration;
    if (native_shutdown_timeout_exit_code != 7) return error.InvalidTigerBeetleConfiguration;
    try validateAddress("127.0.0.1:3000");
    if (!native_enabled) return;

    if (try std.process.hasEnvVar(std.heap.page_allocator, "VOYAGE_API_TB_STALLED_CHILD")) {
        runStalledDeinitChild();
    }
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "VOYAGE_API_TB_ADDRESS")) |address| {
        defer std.heap.page_allocator.free(address);
        try runNativeLookupAndRepeatedInit(address);
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "VOYAGE_API_TB_UNAVAILABLE_ADDRESS")) |address| {
        defer std.heap.page_allocator.free(address);
        try runNativeUnavailable(address);
    } else |err| switch (err) {
        error.EnvironmentVariableNotFound => {},
        else => return err,
    }
    if (try std.process.hasEnvVar(std.heap.page_allocator, "VOYAGE_API_TB_STALLED_PARENT")) {
        try runStalledDeinitParent(std.heap.page_allocator);
    }
}

fn runNativeLookupAndRepeatedInit(address: []const u8) !void {
    for (0..2) |_| {
        var client = try Client.init(std.heap.page_allocator, .{ .address = address });
        const result = try client.healthProbe();
        if (result.result_size != 0) return error.UnexpectedLookupResult;
        if (result.callback_count != 1) return error.CallbackCountInvalid;
        const started = std.time.milliTimestamp();
        try client.deinit();
        const elapsed = std.time.milliTimestamp() - started;
        if (elapsed >= shutdown_watchdog_ms) return error.ClientDeinitTooSlow;
    }
}

fn runNativeUnavailable(address: []const u8) !void {
    var client = try Client.init(std.heap.page_allocator, .{ .address = address });
    const started = std.time.milliTimestamp();
    try expectError(error.RequestTimeout, client.healthProbe());
    const elapsed = std.time.milliTimestamp() - started;
    if (elapsed < request_timeout_ms) return error.RequestReturnedTooSoon;
    if (elapsed >= request_timeout_ms + 2_000) return error.RequestTimeoutExceededBudget;
    client.allocator.destroy(client);
}

fn runStalledDeinitParent(allocator: std.mem.Allocator) !void {
    const executable = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(executable);

    var env = try std.process.getEnvMap(allocator);
    defer env.deinit();
    env.remove("VOYAGE_API_TB_STALLED_PARENT");
    env.remove("VOYAGE_API_TB_ADDRESS");
    env.remove("VOYAGE_API_TB_UNAVAILABLE_ADDRESS");
    try env.put("VOYAGE_API_TB_STALLED_CHILD", "1");

    var child = std.process.Child.init(&.{executable}, allocator);
    child.env_map = &env;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.create_no_window = true;

    var timer = std.time.Timer.start() catch unreachable;
    const term = try child.spawnAndWait();
    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    const exit_code = switch (term) {
        .Exited => |code| code,
        .Signal, .Stopped, .Unknown => return error.StalledChildDidNotExitNormally,
    };
    if (exit_code != native_shutdown_timeout_exit_code) return error.StalledChildExitCodeInvalid;
    if (elapsed_ms > stalled_deinit_parent_limit_ms) return error.StalledChildExceededParentLimit;
}

fn runStalledDeinitChild() noreturn {
    var native: tb.tb_client_t = undefined;
    deinitWithWatchdog(&native, stalledDeinitThread) catch std.process.exit(1);
    std.process.exit(1);
}

fn expectError(expected: anyerror, result: anytype) !void {
    if (result) |_| return error.ExpectedErrorMissing else |actual| {
        if (actual != expected) return actual;
    }
}

test "API-003 constants and diagnostics are stable without native inputs" {
    try selfTest();
    try std.testing.expectEqual(ErrorCode.tigerbeetle_timeout, mapNativeError(error.RequestTimeout));
    try std.testing.expectEqual(ErrorCode.tigerbeetle_unavailable, mapNativeError(error.ClientInitFailed));
    const diagnostic = sanitizedDiagnostic("tigerbeetle_lookup", 42);
    try std.testing.expectEqualStrings("tigerbeetle_lookup", diagnostic.operation);
    try std.testing.expect(!containsSecretLikeText(diagnostic.operation));
    try std.testing.expect(!containsSecretLikeText("tigerbeetle_lookup elapsed_ms=42"));
    try std.testing.expect(containsSecretLikeText("account_id=1"));
}

test "API-003 address validation rejects ambiguous native address text" {
    try std.testing.expectError(error.InvalidAddress, validateAddress(""));
    try std.testing.expectError(error.InvalidAddress, validateAddress("127.0.0.1:3000\n"));
    try validateAddress("127.0.0.1:3000");
}

test "API-003 native lookup health probe succeeds when enabled" {
    if (!native_enabled) return error.SkipZigTest;
    const address = std.process.getEnvVarOwned(std.testing.allocator, "VOYAGE_API_TB_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(address);

    var client = try Client.init(std.testing.allocator, .{ .address = address });
    defer client.deinit() catch {};
    const result = try client.healthProbe();
    try std.testing.expectEqual(@as(u32, 0), result.result_size);
    try std.testing.expectEqual(@as(u32, 1), result.callback_count);
}

test "API-003 native repeated init lookup and deinit stays bounded" {
    if (!native_enabled) return error.SkipZigTest;
    const address = std.process.getEnvVarOwned(std.testing.allocator, "VOYAGE_API_TB_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(address);

    for (0..2) |_| {
        var client = try Client.init(std.testing.allocator, .{ .address = address });
        const result = try client.healthProbe();
        try std.testing.expectEqual(@as(u32, 0), result.result_size);
        const started = std.time.milliTimestamp();
        try client.deinit();
        const elapsed = std.time.milliTimestamp() - started;
        try std.testing.expect(elapsed < shutdown_watchdog_ms);
    }
}

test "API-003 native unavailable server times out and cancels callback" {
    if (!native_enabled) return error.SkipZigTest;
    const address = std.process.getEnvVarOwned(std.testing.allocator, "VOYAGE_API_TB_UNAVAILABLE_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(address);

    var client = try Client.init(std.testing.allocator, .{ .address = address });
    const started = std.time.milliTimestamp();
    try std.testing.expectError(error.RequestTimeout, client.healthProbe());
    const elapsed = std.time.milliTimestamp() - started;
    try std.testing.expect(elapsed >= request_timeout_ms);
    try std.testing.expect(elapsed < request_timeout_ms + 2_000);
    client.allocator.destroy(client);
}

test "API-003 stalled deinit child fixture exits 7 within parent limit" {
    if (!try std.process.hasEnvVar(std.testing.allocator, "VOYAGE_API_TB_STALLED_PARENT")) {
        return error.SkipZigTest;
    }
    const executable = try std.fs.selfExePathAlloc(std.testing.allocator);
    defer std.testing.allocator.free(executable);

    var env = try std.process.getEnvMap(std.testing.allocator);
    defer env.deinit();
    env.remove("VOYAGE_API_TB_STALLED_PARENT");
    env.remove("VOYAGE_API_TB_ADDRESS");
    env.remove("VOYAGE_API_TB_UNAVAILABLE_ADDRESS");
    try env.put("VOYAGE_API_TB_STALLED_CHILD", "1");

    var child = std.process.Child.init(&.{executable}, std.testing.allocator);
    child.env_map = &env;
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.create_no_window = true;

    var timer = std.time.Timer.start() catch unreachable;
    const term = try child.spawnAndWait();
    const elapsed_ms = timer.read() / std.time.ns_per_ms;
    const exit_code = switch (term) {
        .Exited => |code| code,
        .Signal, .Stopped, .Unknown => return error.StalledChildDidNotExitNormally,
    };
    try std.testing.expectEqual(@as(u8, native_shutdown_timeout_exit_code), @as(u8, @intCast(exit_code)));
    try std.testing.expect(elapsed_ms <= stalled_deinit_parent_limit_ms);
}

test "API-003 stalled deinit injected child" {
    if (!try std.process.hasEnvVar(std.testing.allocator, "VOYAGE_API_TB_STALLED_CHILD")) {
        return error.SkipZigTest;
    }
    var native: tb.tb_client_t = undefined;
    try deinitWithWatchdog(&native, stalledDeinitThread);
}

fn stalledDeinitThread(shutdown: *Shutdown, native: *tb.tb_client_t) void {
    _ = shutdown;
    _ = native;
    while (true) {
        std.Thread.sleep(std.time.ns_per_s);
    }
}
