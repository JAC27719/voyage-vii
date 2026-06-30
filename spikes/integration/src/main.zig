const std = @import("std");
const builtin = @import("builtin");
const api = @import("api");
const pg = @import("pg");

const tb = @cImport({
    @cInclude("tb_client.h");
});

const request_timeout_ns = 5 * std.time.ns_per_s;
const shutdown_watchdog_ns = 10 * std.time.ns_per_s;
const query_timeout_ms = 3_000;

const RuntimeConfig = struct {
    pg_host: []const u8,
    pg_port: u16,
    pg_database: []const u8,
    pg_username: []const u8,
    tb_address: []const u8,
};

const Completion = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
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

var runtime_config: RuntimeConfig = undefined;
var runtime_config_set = false;

pub fn main() void {
    run() catch |err| {
        std.debug.print("integration_exit=failed error={s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn run() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) return usage();
    if (std.mem.eql(u8, args[1], "serve")) return serve(allocator, args[2..]);
    if (std.mem.eql(u8, args[1], "probe-once")) return probeOnce(allocator, args[2..]);
    return usage();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        \\usage:
        \\  integration-spike serve <port> <pg-host> <pg-port> <pg-database> <pg-username> <tb-address>
        \\  integration-spike probe-once <pg-host> <pg-port> <pg-database> <pg-username> <tb-address>
        \\
        \\PGPASSWORD supplies the PostgreSQL password and is never printed.
        \\
    , .{});
    return error.InvalidArguments;
}

fn serve(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len != 6) return usage();

    const port = try std.fmt.parseInt(u16, args[0], 10);
    runtime_config = .{
        .pg_host = args[1],
        .pg_port = try std.fmt.parseInt(u16, args[2], 10),
        .pg_database = args[3],
        .pg_username = args[4],
        .tb_address = args[5],
    };
    runtime_config_set = true;

    var app = try api.App.init(allocator, .{
        .title = "FEAS-003",
        .version = "0.0.0",
        .health_url = null,
    });
    defer app.deinit();

    try app.get("/probe", probeEndpoint);
    try app.get("/shutdown", shutdownEndpoint);
    try app.run(.{
        .host = "127.0.0.1",
        .port = port,
        .access_log = false,
        .num_threads = 0,
        .auto_port = false,
        .disable_reserved_routes = true,
    });
}

fn probeOnce(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len != 5) return usage();
    const config: RuntimeConfig = .{
        .pg_host = args[0],
        .pg_port = try std.fmt.parseInt(u16, args[1], 10),
        .pg_database = args[2],
        .pg_username = args[3],
        .tb_address = args[4],
    };
    const result = try runCombinedProbe(allocator, config);
    std.debug.print(
        "integration_probe=passed pg_value={d} tb_result_size={d} tb_callbacks={d} tb_deinit_ms={d}\n",
        .{
            result.pg_value,
            result.tb_result_size,
            result.tb_callbacks,
            result.tb_deinit_ms,
        },
    );
}

fn probeEndpoint(_: *api.Context) api.Response {
    if (!runtime_config_set) {
        return api.Response.err(.internal_server_error, "{\"status\":\"error\",\"reason\":\"config_missing\"}");
    }

    const result = runCombinedProbe(std.heap.page_allocator, runtime_config) catch |err| {
        std.debug.print("integration_probe=failed error={s}\n", .{@errorName(err)});
        return api.Response.err(.internal_server_error, "{\"status\":\"error\",\"dependency\":\"integration\"}");
    };

    std.debug.print(
        "integration_probe=passed pg_value={d} tb_result_size={d} tb_callbacks={d} tb_deinit_ms={d}\n",
        .{
            result.pg_value,
            result.tb_result_size,
            result.tb_callbacks,
            result.tb_deinit_ms,
        },
    );
    return api.Response.jsonRaw("{\"status\":\"ok\",\"postgres\":\"ok\",\"tigerbeetle\":\"ok\"}");
}

fn shutdownEndpoint(_: *api.Context) api.Response {
    const thread = std.Thread.spawn(.{}, delayedExit, .{}) catch {
        std.process.exit(0);
    };
    thread.detach();
    return api.Response.jsonRaw("{\"shutdown\":\"accepted\"}");
}

fn delayedExit() void {
    std.Thread.sleep(50 * std.time.ns_per_ms);
    std.process.exit(0);
}

const CombinedProbeResult = struct {
    pg_value: i32,
    tb_result_size: u32,
    tb_callbacks: u32,
    tb_deinit_ms: u64,
};

fn runCombinedProbe(
    allocator: std.mem.Allocator,
    config: RuntimeConfig,
) !CombinedProbeResult {
    const pg_value = try runPostgresProbe(allocator, config);
    const tb_result = try runTigerBeetleLookup(config.tb_address);
    return .{
        .pg_value = pg_value,
        .tb_result_size = tb_result.result_size,
        .tb_callbacks = tb_result.callbacks,
        .tb_deinit_ms = tb_result.deinit_ms,
    };
}

fn runPostgresProbe(allocator: std.mem.Allocator, config: RuntimeConfig) !i32 {
    const password = std.process.getEnvVarOwned(allocator, "PGPASSWORD") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (password) |value| {
        @memset(value, 0);
        allocator.free(value);
    };

    var conn = pg.Conn.openAndAuth(allocator, .{
        .host = config.pg_host,
        .port = config.pg_port,
        .tls = .off,
    }, .{
        .username = config.pg_username,
        .password = password,
        .database = config.pg_database,
        .timeout = 5_000,
        .application_name = "voyage-vii-feas-003",
    }) catch |err| {
        std.debug.print("pg_probe=failed error={s}\n", .{@errorName(err)});
        return err;
    };
    defer {
        conn.deinit();
        std.debug.print("pg_cleanup=complete\n", .{});
    }

    var row = (try conn.rowOpts("SELECT 1", .{}, .{
        .timeout = query_timeout_ms,
    })) orelse return error.MissingProbeRow;
    defer row.deinit() catch {};

    const value = try row.get(i32, 0);
    if (value != 1) return error.UnexpectedProbeValue;
    std.debug.print("pg_probe=passed value={d}\n", .{value});
    return value;
}

const TigerBeetleProbeResult = struct {
    result_size: u32,
    callbacks: u32,
    deinit_ms: u64,
};

fn runTigerBeetleLookup(address: []const u8) !TigerBeetleProbeResult {
    var completion: Completion = .{};
    var client: tb.tb_client_t = undefined;
    const cluster_id = [_]u8{0} ** 16;

    const init_status = tb.tb_client_init(
        &client,
        &cluster_id,
        address.ptr,
        @intCast(address.len),
        @intFromPtr(&completion),
        onCompletion,
    );
    if (init_status != tb.TB_INIT_SUCCESS) {
        std.debug.print("tb_init_status={d}\n", .{init_status});
        return error.TigerBeetleClientInitFailed;
    }

    var ids = [_]tb.tb_uint128_t{0};
    var packet: tb.tb_packet_t = std.mem.zeroes(tb.tb_packet_t);
    packet.user_data = @ptrCast(&completion);
    packet.data = @ptrCast(&ids);
    packet.data_size = @sizeOf(@TypeOf(ids));
    packet.operation = @intCast(tb.TB_OPERATION_LOOKUP_ACCOUNTS);
    packet.status = @intCast(tb.TB_PACKET_OK);

    const submit_status = tb.tb_client_submit(&client, &packet);
    if (submit_status != tb.TB_CLIENT_OK) {
        _ = deinitWithWatchdog(&client) catch {};
        return error.TigerBeetleClientSubmitFailed;
    }

    const wait_result = waitForCompletion(&completion, request_timeout_ns);
    if (!wait_result.completed) {
        _ = deinitWithWatchdog(&client) catch {};
        return error.TigerBeetleRequestTimeout;
    }
    if (completion.packet_status != tb.TB_PACKET_OK) {
        _ = deinitWithWatchdog(&client) catch {};
        return error.TigerBeetlePacketFailed;
    }
    try verifyCallback(&completion);
    const shutdown_result = try deinitWithWatchdog(&client);

    std.debug.print(
        "tb_lookup=passed result_size={d} callbacks={d} elapsed_ms={d} deinit_ms={d}\n",
        .{
            completion.result_size,
            completion.callback_count,
            wait_result.elapsed_ns / std.time.ns_per_ms,
            shutdown_result.elapsed_ns / std.time.ns_per_ms,
        },
    );
    return .{
        .result_size = completion.result_size,
        .callbacks = completion.callback_count,
        .deinit_ms = shutdown_result.elapsed_ns / std.time.ns_per_ms,
    };
}

const WaitResult = struct {
    completed: bool,
    elapsed_ns: u64,
};

fn waitForCompletion(completion: *Completion, timeout_ns: u64) WaitResult {
    var timer = std.time.Timer.start() catch unreachable;

    completion.mutex.lock();
    defer completion.mutex.unlock();

    while (!completion.completed) {
        const elapsed_ns = timer.read();
        if (elapsed_ns >= timeout_ns) {
            return .{ .completed = false, .elapsed_ns = elapsed_ns };
        }
        completion.condition.timedWait(
            &completion.mutex,
            timeout_ns - elapsed_ns,
        ) catch |err| switch (err) {
            error.Timeout => {
                return .{ .completed = completion.completed, .elapsed_ns = timer.read() };
            },
        };
    }

    return .{ .completed = true, .elapsed_ns = timer.read() };
}

fn deinitWithWatchdog(client: *tb.tb_client_t) !WaitResult {
    var shutdown: Shutdown = .{};
    var thread = try std.Thread.spawn(.{}, realDeinitThread, .{ &shutdown, client });
    return waitForShutdown(&shutdown, &thread);
}

fn realDeinitThread(shutdown: *Shutdown, client: *tb.tb_client_t) void {
    shutdown.complete(@intCast(tb.tb_client_deinit(client)));
}

fn waitForShutdown(shutdown: *Shutdown, thread: *std.Thread) !WaitResult {
    var timer = std.time.Timer.start() catch unreachable;
    var status: i32 = undefined;

    shutdown.mutex.lock();
    while (!shutdown.completed) {
        const elapsed_ns = timer.read();
        if (elapsed_ns >= shutdown_watchdog_ns) {
            shutdown.mutex.unlock();
            std.debug.print("native_shutdown_timeout watchdog_ms={d} exit_code=7\n", .{
                elapsed_ns / std.time.ns_per_ms,
            });
            std.process.exit(7);
        }
        shutdown.condition.timedWait(
            &shutdown.mutex,
            shutdown_watchdog_ns - elapsed_ns,
        ) catch |err| switch (err) {
            error.Timeout => {},
        };
    }
    status = shutdown.status;
    shutdown.mutex.unlock();

    thread.join();

    const elapsed_ns = timer.read();
    if (status != tb.TB_CLIENT_OK) return error.TigerBeetleClientDeinitFailed;
    if (elapsed_ns >= shutdown_watchdog_ns) return error.TigerBeetleClientDeinitTooSlow;
    return .{ .completed = true, .elapsed_ns = elapsed_ns };
}

fn verifyCallback(completion: *Completion) !void {
    completion.mutex.lock();
    defer completion.mutex.unlock();

    if (!completion.completed) return error.TigerBeetleCallbackMissing;
    if (completion.callback_count != 1) return error.TigerBeetleCallbackCountInvalid;
    if (!completion.context_matches) return error.TigerBeetleCallbackContextInvalid;
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

    const completion: *Completion = @ptrFromInt(context_value);
    completion.mutex.lock();
    defer completion.mutex.unlock();

    completion.callback_count += 1;
    completion.packet_status = packet.*.status;
    completion.result_size = result_size;
    completion.context_matches =
        packet.*.user_data == @as(?*anyopaque, @ptrCast(completion));
    completion.completed = true;
    completion.condition.signal();
}

comptime {
    if (builtin.os.tag != .windows) {
        @compileLog("FEAS-003 runtime evidence is Windows-only; non-Windows builds are informational.");
    }
}
