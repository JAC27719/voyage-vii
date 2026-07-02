const std = @import("std");
const builtin = @import("builtin");
const platform = @import("../platform/root.zig");
const api_tigerbeetle = @import("../../tigerbeetle/root.zig");

pub const component_id = "tigerbeetle";
pub const version = "0.17.7";
pub const replica_index: u8 = 0;
pub const replica_count: u8 = 1;
pub const cache_mib: u32 = 128;
pub const graceful_stop_ms: u32 = 10_000;
pub const request_timeout_ms = api_tigerbeetle.request_timeout_ms;
pub const startup_retry_delays_ms = [_]u32{ 1_000, 2_000, 4_000 };
pub const replica_file_name = "0_0.tigerbeetle";
pub const cluster_id_file_name = "cluster-id.hex";
pub const executable_sha256 = "fcb78aa4536e765e2cc15e6f2e222b17c00a325b87e497b1509471682e903a48";
pub const executable_max_bytes = 128 * 1024 * 1024;

const cluster_id_bytes = 16;
const cluster_id_hex_len = cluster_id_bytes * 2;

pub const StorageClassification = enum {
    pristine,
    initialized,
    invalid,
};

pub const LifecycleError = error{
    InvalidTigerBeetleRoot,
    InvalidClusterId,
    RefuseReformat,
    RuntimeAssetMissing,
    RuntimeAssetInvalid,
    PortUnavailable,
};

pub const ClusterId = [cluster_id_bytes]u8;

pub const StartupPaths = struct {
    binary_path: []const u8,
    data_root: []const u8,
};

pub const StartupPlan = struct {
    cluster_id: ClusterId,
    address: []u8,
    format_command: ?CommandLine,
    start_command: CommandLine,

    pub fn deinit(self: *StartupPlan, allocator: std.mem.Allocator) void {
        allocator.free(self.address);
        if (self.format_command) |*command| command.deinit(allocator);
        self.start_command.deinit(allocator);
    }
};

pub const CommandLine = struct {
    argv: []const []const u8,

    pub fn deinit(self: *CommandLine, allocator: std.mem.Allocator) void {
        for (self.argv) |arg| allocator.free(arg);
        allocator.free(self.argv);
    }
};

pub const ShutdownPhase = enum {
    graceful,
    escalate,
    reap,
};

pub const ShutdownPlan = struct {
    graceful_timeout_ms: u32,
    phases: [3]ShutdownPhase,
};

pub const ShutdownOutcome = struct {
    phases: [3]ShutdownPhase,
    escalated: bool,
    term: std.process.Child.Term,
};

pub const ProbeStatus = enum {
    healthy,
    unavailable,
    timeout,
    native_shutdown_timeout,
    internal_error,
};

pub fn classifyDataDirectory(root_path: []const u8) !StorageClassification {
    var root = std.fs.cwd().openDir(root_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .pristine,
        else => return err,
    };
    defer root.close();

    var saw_cluster_id = false;
    var saw_replica = false;
    var iterator = root.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) return .invalid;
        if (std.mem.eql(u8, entry.name, cluster_id_file_name)) {
            if (saw_cluster_id) return .invalid;
            saw_cluster_id = true;
        } else if (std.mem.eql(u8, entry.name, replica_file_name)) {
            if (saw_replica) return .invalid;
            saw_replica = true;
        } else {
            return .invalid;
        }
    }

    if (!saw_cluster_id and !saw_replica) return .pristine;
    if (saw_cluster_id and saw_replica) {
        _ = try readClusterId(root_path);
        return .initialized;
    }
    return .invalid;
}

pub fn makeStartupPlan(
    allocator: std.mem.Allocator,
    paths: StartupPaths,
    port: u16,
    cluster_id: ?ClusterId,
) !StartupPlan {
    try validateRuntimeBinary(paths.binary_path);
    return makeStartupPlanAfterValidation(allocator, paths, port, cluster_id);
}

fn makeStartupPlanAfterValidation(
    allocator: std.mem.Allocator,
    paths: StartupPaths,
    port: u16,
    cluster_id: ?ClusterId,
) !StartupPlan {
    const address = try loopbackAddress(allocator, port);
    errdefer allocator.free(address);

    return switch (try classifyDataDirectory(paths.data_root)) {
        .pristine => blk: {
            const id = cluster_id orelse generateClusterId();
            try persistClusterId(paths.data_root, id);
            errdefer removePersistedClusterId(paths.data_root);
            const format_command = try buildFormatCommand(allocator, paths.binary_path, paths.data_root, id);
            errdefer {
                var owned = format_command;
                owned.deinit(allocator);
            }
            const start_command = try buildStartCommand(allocator, paths.binary_path, paths.data_root, address);
            break :blk .{
                .cluster_id = id,
                .address = address,
                .format_command = format_command,
                .start_command = start_command,
            };
        },
        .initialized => blk: {
            const id = try readClusterId(paths.data_root);
            const start_command = try buildStartCommand(allocator, paths.binary_path, paths.data_root, address);
            break :blk .{
                .cluster_id = id,
                .address = address,
                .format_command = null,
                .start_command = start_command,
            };
        },
        .invalid => return error.RefuseReformat,
    };
}

pub fn reserveDynamicAddress(allocator: std.mem.Allocator) !struct {
    reservation: platform.LoopbackReservation,
    address: []u8,
} {
    var reservation = platform.reserveLoopbackPort() catch |err| switch (err) {
        error.AddressInUse => return error.PortUnavailable,
        else => return err,
    };
    errdefer reservation.release();
    return .{
        .reservation = reservation,
        .address = try loopbackAddress(allocator, reservation.port),
    };
}

pub fn buildFormatCommand(
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    data_root: []const u8,
    cluster_id: ClusterId,
) !CommandLine {
    const replica_path = try std.fs.path.join(allocator, &.{ data_root, replica_file_name });
    defer allocator.free(replica_path);
    const cluster_decimal = try clusterIdDecimal(allocator, cluster_id);
    defer allocator.free(cluster_decimal);
    const cluster_arg = try std.fmt.allocPrint(allocator, "--cluster={s}", .{cluster_decimal});
    defer allocator.free(cluster_arg);
    return duplicateArgs(allocator, &.{
        binary_path,
        "format",
        cluster_arg,
        "--replica=0",
        "--replica-count=1",
        "--development",
        replica_path,
    });
}

pub fn buildStartCommand(
    allocator: std.mem.Allocator,
    binary_path: []const u8,
    data_root: []const u8,
    address: []const u8,
) !CommandLine {
    const replica_path = try std.fs.path.join(allocator, &.{ data_root, replica_file_name });
    defer allocator.free(replica_path);
    const address_arg = try std.fmt.allocPrint(allocator, "--addresses={s}", .{address});
    defer allocator.free(address_arg);
    return duplicateArgs(allocator, &.{
        binary_path,
        "start",
        "--development=true",
        address_arg,
        "--cache-grid=128MiB",
        replica_path,
    });
}

pub fn retryDelayMs(attempt_index: usize) ?u32 {
    if (attempt_index >= startup_retry_delays_ms.len) return null;
    return startup_retry_delays_ms[attempt_index];
}

pub fn shutdownPlan() ShutdownPlan {
    return .{
        .graceful_timeout_ms = graceful_stop_ms,
        .phases = .{ .graceful, .escalate, .reap },
    };
}

pub fn shutdownContained(
    containment: platform.ProcessContainment,
    process: platform.ContainedProcess,
) !ShutdownOutcome {
    return shutdownContainedWithTimeout(containment, process, graceful_stop_ms);
}

pub fn shutdownContainedWithTimeout(
    containment: platform.ProcessContainment,
    process: platform.ContainedProcess,
    graceful_timeout_ms: u32,
) !ShutdownOutcome {
    var wait_state = WaitState{};
    var wait_thread = try std.Thread.spawn(.{}, waitContainedThread, .{ &wait_state, process });
    const completed_gracefully = waitForProcess(&wait_state, graceful_timeout_ms);
    if (!completed_gracefully) {
        platform.terminateContainment(containment, 1);
    }
    wait_thread.join();
    if (wait_state.err) |err| return err;
    const term = wait_state.term orelse return error.ProcessDidNotReap;
    return .{
        .phases = .{ .graceful, .escalate, .reap },
        .escalated = !completed_gracefully,
        .term = term,
    };
}

const WaitState = struct {
    mutex: std.Thread.Mutex = .{},
    condition: std.Thread.Condition = .{},
    completed: bool = false,
    term: ?std.process.Child.Term = null,
    err: ?anyerror = null,
};

fn waitContainedThread(state: *WaitState, process: platform.ContainedProcess) void {
    const result = platform.waitContained(process);
    state.mutex.lock();
    defer state.mutex.unlock();
    if (result) |term| {
        state.term = term;
    } else |err| {
        state.err = err;
    }
    state.completed = true;
    state.condition.signal();
}

fn waitForProcess(state: *WaitState, timeout_ms: u32) bool {
    var timer = std.time.Timer.start() catch unreachable;
    state.mutex.lock();
    defer state.mutex.unlock();
    while (!state.completed) {
        const elapsed_ns = timer.read();
        const timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
        if (elapsed_ns >= timeout_ns) return false;
        state.condition.timedWait(&state.mutex, timeout_ns - elapsed_ns) catch |err| switch (err) {
            error.Timeout => return state.completed,
        };
    }
    return true;
}

pub fn probe(address: []const u8, cluster_id: ClusterId) !api_tigerbeetle.ProbeResult {
    var client = try api_tigerbeetle.Client.init(std.heap.page_allocator, .{
        .address = address,
        .cluster_id = cluster_id,
    });
    defer client.deinit() catch {};
    return client.healthProbe();
}

pub fn probeStatus(address: []const u8, cluster_id: ClusterId) ProbeStatus {
    var client = api_tigerbeetle.Client.init(std.heap.page_allocator, .{
        .address = address,
        .cluster_id = cluster_id,
    }) catch |err| return probeStatusFromError(api_tigerbeetle.mapNativeError(err));
    defer client.deinit() catch {};
    _ = client.healthProbe() catch |err| return probeStatusFromError(api_tigerbeetle.mapNativeError(err));
    return .healthy;
}

pub fn verifyLoopbackPortAvailable(port: u16) !void {
    if (port == 0) return error.PortUnavailable;
    const address = try std.net.Address.parseIp4("127.0.0.1", port);
    var server = address.listen(.{ .reuse_address = false }) catch |err| switch (err) {
        error.AddressInUse => return error.PortUnavailable,
        else => return err,
    };
    server.deinit();
}

pub fn waitForListening(address: []const u8, timeout_ms: u32) !void {
    const port = try parseLoopbackPort(address);
    const endpoint = try std.net.Address.parseIp4("127.0.0.1", port);
    var timer = std.time.Timer.start() catch unreachable;
    const timeout_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
    while (timer.read() < timeout_ns) {
        const stream = std.net.tcpConnectToAddress(endpoint) catch |err| switch (err) {
            error.ConnectionRefused, error.ConnectionTimedOut, error.NetworkUnreachable, error.AddressNotAvailable => {
                sleepMs(100);
                continue;
            },
            else => return err,
        };
        stream.close();
        return;
    }
    return error.PortUnavailable;
}

pub fn validateRuntimeBinary(binary_path: []const u8) !void {
    if (!std.fs.path.isAbsolute(binary_path)) return error.RuntimeAssetInvalid;
    const basename = std.fs.path.basename(binary_path);
    const expected = if (builtin.os.tag == .windows) "tigerbeetle.exe" else "tigerbeetle";
    if (!std.ascii.eqlIgnoreCase(basename, expected)) return error.RuntimeAssetInvalid;
    const bytes = std.fs.cwd().readFileAlloc(std.heap.page_allocator, binary_path, executable_max_bytes) catch |err| switch (err) {
        error.FileNotFound => return error.RuntimeAssetMissing,
        else => return error.RuntimeAssetInvalid,
    };
    defer std.heap.page_allocator.free(bytes);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const actual = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &actual, executable_sha256)) return error.RuntimeAssetInvalid;
}

pub fn persistClusterId(root_path: []const u8, cluster_id: ClusterId) !void {
    try std.fs.cwd().makePath(root_path);
    var root = try std.fs.cwd().openDir(root_path, .{});
    defer root.close();

    const encoded = std.fmt.bytesToHex(cluster_id, .lower);
    try root.writeFile(.{ .sub_path = cluster_id_file_name, .data = &encoded });
}

pub fn readClusterId(root_path: []const u8) !ClusterId {
    var root = try std.fs.cwd().openDir(root_path, .{});
    defer root.close();
    const bytes = try root.readFileAlloc(std.heap.page_allocator, cluster_id_file_name, cluster_id_hex_len + 1);
    defer std.heap.page_allocator.free(bytes);
    if (bytes.len != cluster_id_hex_len) return error.InvalidClusterId;
    return parseClusterId(bytes);
}

pub fn parseClusterId(hex: []const u8) !ClusterId {
    if (hex.len != cluster_id_hex_len) return error.InvalidClusterId;
    var result: ClusterId = undefined;
    _ = std.fmt.hexToBytes(&result, hex) catch return error.InvalidClusterId;
    return result;
}

pub fn loopbackAddress(allocator: std.mem.Allocator, port: u16) ![]u8 {
    if (port == 0) return error.PortUnavailable;
    return std.fmt.allocPrint(allocator, "127.0.0.1:{d}", .{port});
}

fn parseLoopbackPort(address: []const u8) !u16 {
    const prefix = "127.0.0.1:";
    if (!std.mem.startsWith(u8, address, prefix)) return error.PortUnavailable;
    const port = std.fmt.parseInt(u16, address[prefix.len..], 10) catch return error.PortUnavailable;
    if (port == 0) return error.PortUnavailable;
    return port;
}

fn removePersistedClusterId(root_path: []const u8) void {
    var root = std.fs.cwd().openDir(root_path, .{}) catch return;
    defer root.close();
    root.deleteFile(cluster_id_file_name) catch {};
}

fn generateClusterId() ClusterId {
    var bytes: ClusterId = undefined;
    std.crypto.random.bytes(&bytes);
    return bytes;
}

fn clusterIdDecimal(allocator: std.mem.Allocator, cluster_id: ClusterId) ![]u8 {
    const value = std.mem.readInt(u128, &cluster_id, .little);
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

fn duplicateArgs(allocator: std.mem.Allocator, args: []const []const u8) !CommandLine {
    var argv = try allocator.alloc([]const u8, args.len);
    var initialized: usize = 0;
    errdefer {
        for (argv[0..initialized]) |arg| allocator.free(arg);
        allocator.free(argv);
    }
    for (args, 0..) |arg, index| {
        argv[index] = try allocator.dupe(u8, arg);
        initialized += 1;
    }
    return .{ .argv = argv };
}

pub fn sleepMs(milliseconds: u32) void {
    std.Thread.sleep(@as(u64, milliseconds) * std.time.ns_per_ms);
}

fn probeStatusFromError(code: api_tigerbeetle.ErrorCode) ProbeStatus {
    return switch (code) {
        .tigerbeetle_unavailable => .unavailable,
        .tigerbeetle_timeout => .timeout,
        .native_shutdown_timeout => .native_shutdown_timeout,
        .internal_error => .internal_error,
    };
}

pub fn selfTest() !void {
    if (!std.mem.eql(u8, component_id, "tigerbeetle")) return error.InvalidTigerBeetleLifecycle;
    if (!std.mem.eql(u8, version, "0.17.7")) return error.InvalidTigerBeetleLifecycle;
    if (cache_mib != 128) return error.InvalidTigerBeetleLifecycle;
    if (graceful_stop_ms != 10_000) return error.InvalidTigerBeetleLifecycle;
    if (request_timeout_ms != 5_000) return error.InvalidTigerBeetleLifecycle;
    if (retryDelayMs(0) != 1_000) return error.InvalidTigerBeetleLifecycle;
    if (retryDelayMs(1) != 2_000) return error.InvalidTigerBeetleLifecycle;
    if (retryDelayMs(2) != 4_000) return error.InvalidTigerBeetleLifecycle;
    if (retryDelayMs(3) != null) return error.InvalidTigerBeetleLifecycle;
    const shutdown = shutdownPlan();
    if (shutdown.graceful_timeout_ms != 10_000) return error.InvalidTigerBeetleLifecycle;
    if (shutdown.phases[0] != .graceful) return error.InvalidTigerBeetleLifecycle;
    if (shutdown.phases[1] != .escalate) return error.InvalidTigerBeetleLifecycle;
    if (shutdown.phases[2] != .reap) return error.InvalidTigerBeetleLifecycle;
}

test "RUNTIME-003 classifies pristine initialized and invalid storage" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tb" });
    defer std.testing.allocator.free(root_path);

    try std.testing.expectEqual(StorageClassification.pristine, try classifyDataDirectory(root_path));
    try tmp.dir.makePath("tb");
    try std.testing.expectEqual(StorageClassification.pristine, try classifyDataDirectory(root_path));
    try tmp.dir.writeFile(.{ .sub_path = "tb/random.txt", .data = "do not touch" });
    try std.testing.expectEqual(StorageClassification.invalid, try classifyDataDirectory(root_path));
}

test "RUNTIME-003 persists cluster id and refuses partial data" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tb" });
    defer std.testing.allocator.free(root_path);

    const id = [_]u8{0xaa} ** cluster_id_bytes;
    try persistClusterId(root_path, id);
    try std.testing.expectEqual(StorageClassification.invalid, try classifyDataDirectory(root_path));
    try tmp.dir.writeFile(.{ .sub_path = "tb/0_0.tigerbeetle", .data = "fixture" });
    try std.testing.expectEqual(StorageClassification.initialized, try classifyDataDirectory(root_path));
    const loaded = try readClusterId(root_path);
    try std.testing.expectEqualSlices(u8, &id, &loaded);
}

test "RUNTIME-003 builds commands with one replica dynamic address and 128 MiB cache" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const binary_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tigerbeetle.exe" });
    defer std.testing.allocator.free(binary_path);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tb" });
    defer std.testing.allocator.free(root_path);

    const id = [_]u8{0} ** 15 ++ [_]u8{42};
    var plan = try makeStartupPlanAfterValidation(std.testing.allocator, .{
        .binary_path = binary_path,
        .data_root = root_path,
    }, 30_001, id);
    defer plan.deinit(std.testing.allocator);

    try std.testing.expect(plan.format_command != null);
    try std.testing.expectEqualStrings("127.0.0.1:30001", plan.address);
    try expectArg(plan.start_command, "--development=true");
    try expectArg(plan.start_command, "--cache-grid=128MiB");
    try expectArg(plan.start_command, "--addresses=127.0.0.1:30001");
    try expectArg(plan.format_command.?, "--replica-count=1");
    try expectArg(plan.format_command.?, "--replica=0");
    try expectArg(plan.format_command.?, "--cluster=55827575822966466661959896531774472192");
    try std.testing.expectEqual(StorageClassification.invalid, try classifyDataDirectory(root_path));
}

test "RUNTIME-003 formats cluster id with native little-endian order" {
    const id = [_]u8{1} ++ [_]u8{0} ** 15;
    const decimal = try clusterIdDecimal(std.testing.allocator, id);
    defer std.testing.allocator.free(decimal);
    try std.testing.expectEqualStrings("1", decimal);
}

test "RUNTIME-003 retained run skips format" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const binary_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tigerbeetle.exe" });
    defer std.testing.allocator.free(binary_path);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tb" });
    defer std.testing.allocator.free(root_path);

    const id = [_]u8{0xbb} ** cluster_id_bytes;
    try persistClusterId(root_path, id);
    try tmp.dir.writeFile(.{ .sub_path = "tb/0_0.tigerbeetle", .data = "fixture" });

    var plan = try makeStartupPlanAfterValidation(std.testing.allocator, .{
        .binary_path = binary_path,
        .data_root = root_path,
    }, 30_002, null);
    defer plan.deinit(std.testing.allocator);
    try std.testing.expect(plan.format_command == null);
    try std.testing.expectEqualSlices(u8, &id, &plan.cluster_id);
}

test "RUNTIME-003 refuses damaged data and leaves it untouched" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const binary_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tigerbeetle.exe" });
    defer std.testing.allocator.free(binary_path);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tb" });
    defer std.testing.allocator.free(root_path);
    try tmp.dir.makePath("tb");
    try tmp.dir.writeFile(.{ .sub_path = "tb/0_0.tigerbeetle", .data = "damaged" });

    try std.testing.expectError(error.RefuseReformat, makeStartupPlanAfterValidation(std.testing.allocator, .{
        .binary_path = binary_path,
        .data_root = root_path,
    }, 30_003, null));
    const contents = try tmp.dir.readFileAlloc(std.testing.allocator, "tb/0_0.tigerbeetle", 64);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("damaged", contents);
}

test "RUNTIME-003 validates wrong binary and occupied port behavior" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const wrong_binary = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "not-tigerbeetle.exe" });
    defer std.testing.allocator.free(wrong_binary);
    try tmp.dir.writeFile(.{ .sub_path = "not-tigerbeetle.exe", .data = "fixture" });
    try std.testing.expectError(error.RuntimeAssetInvalid, validateRuntimeBinary(wrong_binary));
    const renamed_fixture = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "tigerbeetle.exe" });
    defer std.testing.allocator.free(renamed_fixture);
    try tmp.dir.writeFile(.{ .sub_path = "tigerbeetle.exe", .data = "fixture" });
    try std.testing.expectError(error.RuntimeAssetInvalid, validateRuntimeBinary(renamed_fixture));
    try std.testing.expectError(error.PortUnavailable, loopbackAddress(std.testing.allocator, 0));
    try std.testing.expectError(error.PortUnavailable, waitForListening("127.0.0.1:0", 1));

    var reservation = try platform.reserveLoopbackPort();
    defer reservation.release();
    try std.testing.expectError(error.PortUnavailable, verifyLoopbackPortAvailable(reservation.port));
}

test "RUNTIME-003 exposes retry and shutdown policy" {
    try selfTest();
}

test "RUNTIME-003 applies graceful wait escalation and reap to contained process" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const containment = try platform.initKillOnCloseContainment();
    defer platform.closeContainment(containment);
    const child = try platform.spawnContained(
        containment,
        std.testing.allocator,
        &.{ "powershell", "-NoProfile", "-Command", "Start-Sleep -Seconds 30" },
    );
    const outcome = try shutdownContainedWithTimeout(containment, child, 50);
    try std.testing.expect(outcome.escalated);
    try std.testing.expectEqual(ShutdownPhase.graceful, outcome.phases[0]);
    try std.testing.expectEqual(ShutdownPhase.escalate, outcome.phases[1]);
    try std.testing.expectEqual(ShutdownPhase.reap, outcome.phases[2]);
}

fn expectArg(command: CommandLine, expected: []const u8) !void {
    for (command.argv) |arg| {
        if (std.mem.eql(u8, arg, expected)) return;
    }
    return error.ExpectedArgumentMissing;
}
