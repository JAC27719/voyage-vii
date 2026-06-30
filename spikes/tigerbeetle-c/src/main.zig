const std = @import("std");
const builtin = @import("builtin");

const tb = @cImport({
    @cInclude("tb_client.h");
});

const request_timeout_ns = 5 * std.time.ns_per_s;
const shutdown_watchdog_ns = 10 * std.time.ns_per_s;
const fake_parent_limit_ns = 12 * std.time.ns_per_s;
const native_shutdown_timeout_exit_code: u8 = 7;

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

const Mode = enum {
    lookup,
    unavailable,
    shutdown,
    fake_stalled_parent,
    fake_stalled_child,
};

const DeinitResult = struct {
    elapsed_ns: u64,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage(args[0]);
        return error.InvalidArguments;
    }

    const mode = std.meta.stringToEnum(Mode, args[1]) orelse
        return error.InvalidMode;

    std.debug.print(
        "native_target={s}-{s} pointer_bits={d}\n",
        .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), @bitSizeOf(usize) },
    );

    switch (mode) {
        .lookup, .unavailable, .shutdown => {
            if (args.len != 3) {
                printUsage(args[0]);
                return error.InvalidArguments;
            }
            try runClient(mode, args[2]);
        },
        .fake_stalled_parent => {
            if (args.len != 2) {
                printUsage(args[0]);
                return error.InvalidArguments;
            }
            try runFakeStalledParent(allocator, args[0]);
        },
        .fake_stalled_child => {
            if (args.len != 2) {
                printUsage(args[0]);
                return error.InvalidArguments;
            }
            runFakeStalledChild();
        },
    }
}

fn printUsage(arg0: []const u8) void {
    std.debug.print(
        "usage: {s} <lookup|unavailable|shutdown> <address>\n" ++
            "       {s} fake_stalled_parent\n",
        .{ arg0, arg0 },
    );
}

fn runClient(mode: Mode, address: []const u8) !void {
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
        std.debug.print("init_status={d}\n", .{init_status});
        return error.ClientInitFailed;
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
        return error.ClientSubmitFailed;
    }

    switch (mode) {
        .lookup => {
            const wait_result = waitForCompletion(&completion, request_timeout_ns);
            if (!wait_result.completed) {
                const shutdown_result = try deinitAndVerifyCancellation(&client, &completion);
                std.debug.print(
                    "lookup=timeout elapsed_ms={d} deinit_ms={d} cleanup=ok\n",
                    .{
                        wait_result.elapsed_ns / std.time.ns_per_ms,
                        shutdown_result.elapsed_ns / std.time.ns_per_ms,
                    },
                );
                return error.RequestTimeout;
            }

            if (completion.packet_status != tb.TB_PACKET_OK) {
                _ = deinitWithWatchdog(&client) catch {};
                return error.PacketFailed;
            }
            try verifyCallback(&completion);
            const shutdown_result = try deinitWithWatchdog(&client);
            std.debug.print(
                "lookup=ok result_size={d} callbacks={d} elapsed_ms={d} deinit_ms={d} cleanup=ok\n",
                .{
                    completion.result_size,
                    completion.callback_count,
                    wait_result.elapsed_ns / std.time.ns_per_ms,
                    shutdown_result.elapsed_ns / std.time.ns_per_ms,
                },
            );
        },
        .unavailable => {
            const wait_result = waitForCompletion(&completion, request_timeout_ns);
            if (wait_result.completed) {
                _ = deinitWithWatchdog(&client) catch {};
                return error.UnavailableCompletedUnexpectedly;
            }

            const shutdown_result = try deinitAndVerifyCancellation(&client, &completion);
            std.debug.print(
                "unavailable=timeout timeout_ms={d} callback_status={d} callbacks={d} deinit_ms={d} cleanup=ok\n",
                .{
                    wait_result.elapsed_ns / std.time.ns_per_ms,
                    completion.packet_status,
                    completion.callback_count,
                    shutdown_result.elapsed_ns / std.time.ns_per_ms,
                },
            );
        },
        .shutdown => {
            const shutdown_result = try deinitAndVerifyCancellation(&client, &completion);
            std.debug.print(
                "shutdown=ok callback_status={d} callbacks={d} deinit_ms={d} cleanup=ok\n",
                .{
                    completion.packet_status,
                    completion.callback_count,
                    shutdown_result.elapsed_ns / std.time.ns_per_ms,
                },
            );
        },
        .fake_stalled_parent, .fake_stalled_child => unreachable,
    }
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

fn deinitWithWatchdog(client: *tb.tb_client_t) !DeinitResult {
    var shutdown: Shutdown = .{};
    var thread = try std.Thread.spawn(.{}, realDeinitThread, .{ &shutdown, client });
    return waitForShutdown(&shutdown, &thread);
}

fn realDeinitThread(shutdown: *Shutdown, client: *tb.tb_client_t) void {
    shutdown.complete(@intCast(tb.tb_client_deinit(client)));
}

fn deinitAndVerifyCancellation(
    client: *tb.tb_client_t,
    completion: *Completion,
) !DeinitResult {
    const shutdown_result = try deinitWithWatchdog(client);
    try verifyCallback(completion);
    if (completion.packet_status != tb.TB_PACKET_CLIENT_SHUTDOWN) {
        return error.ShutdownDidNotCancelPacket;
    }
    return shutdown_result;
}

fn waitForShutdown(shutdown: *Shutdown, thread: *std.Thread) !DeinitResult {
    var timer = std.time.Timer.start() catch unreachable;
    var status: i32 = undefined;

    shutdown.mutex.lock();
    while (!shutdown.completed) {
        const elapsed_ns = timer.read();
        if (elapsed_ns >= shutdown_watchdog_ns) {
            shutdown.mutex.unlock();
            std.debug.print(
                "native_shutdown_timeout watchdog_ms={d} exit_code={d}\n",
                .{
                    elapsed_ns / std.time.ns_per_ms,
                    native_shutdown_timeout_exit_code,
                },
            );
            std.process.exit(native_shutdown_timeout_exit_code);
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
    if (status != tb.TB_CLIENT_OK) return error.ClientDeinitFailed;
    if (elapsed_ns >= shutdown_watchdog_ns) return error.ClientDeinitTooSlow;
    return .{ .elapsed_ns = elapsed_ns };
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

fn runFakeStalledParent(allocator: std.mem.Allocator, executable_path: []const u8) !void {
    const argv = [_][]const u8{ executable_path, "fake_stalled_child" };
    var timer = std.time.Timer.start() catch unreachable;
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    child.create_no_window = true;

    const term = try child.spawnAndWait();
    const elapsed_ns = timer.read();
    const exit_code = switch (term) {
        .Exited => |code| code,
        .Signal, .Stopped, .Unknown => return error.FakeChildDidNotExitNormally,
    };

    if (exit_code != native_shutdown_timeout_exit_code) {
        return error.FakeChildExitCodeInvalid;
    }
    if (elapsed_ns > fake_parent_limit_ns) {
        return error.FakeChildExceededParentLimit;
    }

    std.debug.print(
        "fake_stalled_deinit=ok child_exit={d} wall_ms={d} limit_ms={d} no_surviving_process=true\n",
        .{
            exit_code,
            elapsed_ns / std.time.ns_per_ms,
            fake_parent_limit_ns / std.time.ns_per_ms,
        },
    );
}

fn runFakeStalledChild() noreturn {
    var shutdown: Shutdown = .{};
    var thread = std.Thread.spawn(.{}, stalledDeinitThread, .{&shutdown}) catch {
        std.process.exit(1);
    };
    _ = waitForShutdown(&shutdown, &thread) catch {
        std.process.exit(1);
    };
    std.process.exit(0);
}

fn stalledDeinitThread(shutdown: *Shutdown) void {
    _ = shutdown;
    while (true) {
        std.Thread.sleep(std.time.ns_per_s);
    }
}
