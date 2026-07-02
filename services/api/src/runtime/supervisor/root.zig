const std = @import("std");
const builtin = @import("builtin");
const status = @import("../../status/root.zig");
const sqlite_adapter = @import("../../sqlite/root.zig");
const api_tigerbeetle = @import("../../tigerbeetle/root.zig");
const tigerbeetle = @import("../tigerbeetle/root.zig");
const platform = @import("../platform/root.zig");

pub const restart_budget_count = 3;
pub const initial_readiness_timeout_ms: u32 = 60_000;
pub const idle_memory_budget_bytes: usize = 500 * 1024 * 1024;
pub const native_shutdown_timeout_exit_code: u8 = 7;
pub const sqlite_close_checkpoint_timeout_ms: u32 = 10_000;
pub const startup_retry_delays_ms = [_]u32{ 1_000, 2_000, 4_000 };
const sqlite_dir_name = "sqlite";
const sqlite_database_file_name = "voyage-vii.sqlite3";

pub const Config = struct {
    runtime_root: []const u8,
    data_root: []const u8,
};

pub const ExternalConfig = struct {
    sqlite_path: []const u8,
    tigerbeetle_address: []const u8,
};

pub const ManagedRuntime = struct {
    allocator: std.mem.Allocator,
    config: Config,
    external_config: ?ExternalConfig = null,
    mutex: std.Thread.Mutex = .{},
    snapshot_value: status.Snapshot = status.Snapshot.init(),
    started_ms: i64,
    root_lock: ?platform.RootLock = null,
    sqlite_database: ?sqlite_adapter.Database = null,
    sqlite_database_path: ?[]u8 = null,
    tigerbeetle_client: ?*api_tigerbeetle.Client = null,
    tigerbeetle_containment: ?platform.ProcessContainment = null,
    tigerbeetle_process: ?platform.ContainedProcess = null,
    tigerbeetle_address: ?[]u8 = null,
    tigerbeetle_cluster_id: ?tigerbeetle.ClusterId = null,
    shutdown_started: bool = false,
    startup_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, config: Config) ManagedRuntime {
        return .{
            .allocator = allocator,
            .config = config,
            .started_ms = std.time.milliTimestamp(),
        };
    }

    pub fn startAsync(self: *ManagedRuntime) !void {
        self.startup_thread = try std.Thread.spawn(.{}, startupThread, .{self});
    }

    pub fn startExternalAsync(self: *ManagedRuntime, external: ExternalConfig) !void {
        self.external_config = .{
            .sqlite_path = try self.allocator.dupe(u8, external.sqlite_path),
            .tigerbeetle_address = try self.allocator.dupe(u8, external.tigerbeetle_address),
        };
        errdefer {
            self.allocator.free(self.external_config.?.sqlite_path);
            self.allocator.free(self.external_config.?.tigerbeetle_address);
            self.external_config = null;
        }
        self.startup_thread = try std.Thread.spawn(.{}, startupThread, .{self});
    }

    pub fn snapshot(self: *ManagedRuntime) status.Snapshot {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.snapshot_value;
    }

    pub fn mergeHttpSnapshotAndPlan(self: *ManagedRuntime, previous: status.Snapshot, next: status.Snapshot) RuntimeActions {
        self.mutex.lock();
        defer self.mutex.unlock();
        var actions = RuntimeActions{};
        if (next.sqlite.retry_active and !previous.sqlite.retry_active) {
            actions.retry_sqlite = self.snapshot_value.markRetry(.sqlite);
        }
        if (next.tigerbeetle.retry_active and !previous.tigerbeetle.retry_active) {
            actions.retry_tigerbeetle = self.snapshot_value.markRetry(.tigerbeetle);
        }
        if (next.overall_state == .stopping and previous.overall_state != .stopping) {
            actions.shutdown = self.snapshot_value.markStopping();
        }
        return actions;
    }

    pub fn runRetry(self: *ManagedRuntime, component: status.ComponentId) void {
        switch (component) {
            .sqlite => self.retrySqlite() catch |err| self.markUnhealthy(.sqlite, err),
            .tigerbeetle => self.retryTigerBeetle() catch |err| self.markUnhealthy(.tigerbeetle, err),
        }
    }

    pub fn shutdown(self: *ManagedRuntime) void {
        self.mutex.lock();
        if (self.shutdown_started) {
            self.mutex.unlock();
            self.joinStartupThread();
            return;
        }
        self.shutdown_started = true;
        _ = self.snapshot_value.markStopping();
        self.mutex.unlock();

        self.joinStartupThread();

        if (self.sqlite_database) |*database| {
            checkpointSqlite(database.*) catch {};
            database.close() catch {};
            self.sqlite_database = null;
        }
        if (self.sqlite_database_path) |path| {
            self.allocator.free(path);
            self.sqlite_database_path = null;
        }

        self.closeTigerBeetleClient();
        if (self.tigerbeetle_containment) |containment| {
            if (self.tigerbeetle_process) |process| {
                _ = tigerbeetle.shutdownContained(containment, process) catch {};
                self.tigerbeetle_process = null;
            }
            platform.closeContainment(containment);
            self.tigerbeetle_containment = null;
        }

        if (self.tigerbeetle_address) |address| {
            self.allocator.free(address);
            self.tigerbeetle_address = null;
        }

        if (self.root_lock) |*lock| {
            lock.release();
            self.root_lock = null;
        }
        if (self.external_config) |external| {
            self.allocator.free(external.sqlite_path);
            self.allocator.free(external.tigerbeetle_address);
            self.external_config = null;
        }

        self.mutex.lock();
        self.snapshot_value.sqlite.state = .stopped;
        self.snapshot_value.sqlite.retry_active = false;
        self.snapshot_value.tigerbeetle.state = .stopped;
        self.snapshot_value.tigerbeetle.retry_active = false;
        self.mutex.unlock();
    }

    pub fn deinit(self: *ManagedRuntime) void {
        self.shutdown();
    }

    fn startupThread(self: *ManagedRuntime) void {
        const result = if (self.external_config == null)
            self.startManaged()
        else
            self.startExternal();
        result catch |err| {
            if (!self.isShutdownStarted()) self.markStartupFailure(err);
        };
    }

    fn startManaged(self: *ManagedRuntime) !void {
        try std.fs.cwd().makePath(self.config.data_root);
        self.root_lock = try platform.acquireRootLock(self.config.data_root);
        try self.validateManagedAssets();

        self.startComponentWithRetries(.sqlite);
        self.startComponentWithRetries(.tigerbeetle);

        const elapsed_ms = std.time.milliTimestamp() - self.started_ms;
        if (elapsed_ms > initial_readiness_timeout_ms) return error.ReadinessDeadlineExceeded;
        self.refreshOverall();
        try self.recordIdleMemory();
    }

    fn startExternal(self: *ManagedRuntime) !void {
        try std.fs.cwd().makePath(self.config.data_root);
        self.root_lock = try platform.acquireRootLock(self.config.data_root);
        try self.ensureExternalSqliteParent();

        self.startComponentWithRetries(.sqlite);
        self.startComponentWithRetries(.tigerbeetle);

        const elapsed_ms = std.time.milliTimestamp() - self.started_ms;
        if (elapsed_ms > initial_readiness_timeout_ms) return error.ReadinessDeadlineExceeded;
        self.refreshOverall();
        try self.recordIdleMemory();
    }

    fn startComponentWithRetries(self: *ManagedRuntime, component: status.ComponentId) void {
        var attempt: usize = 0;
        while (attempt <= startup_retry_delays_ms.len) : (attempt += 1) {
            if (self.isShutdownStarted()) return;
            self.markStarting(component, attempt > 0, true);
            const result = switch (component) {
                .sqlite => self.openSqliteForStartup(),
                .tigerbeetle => self.startTigerBeetleForStartup(),
            };
            if (result) |_| {
                self.markHealthy(component);
                return;
            } else |err| {
                const will_retry = attempt < startup_retry_delays_ms.len;
                self.markAttemptFailed(component, err, will_retry);
                if (will_retry) sleepMs(startup_retry_delays_ms[attempt]);
            }
        }
    }

    fn openSqliteForStartup(self: *ManagedRuntime) !void {
        self.sqlite_database = try self.openSqlite();
    }

    fn startTigerBeetleForStartup(self: *ManagedRuntime) !void {
        try self.startTigerBeetle();
    }

    fn retrySqlite(self: *ManagedRuntime) !void {
        if (self.sqlite_database) |*database| {
            checkpointSqlite(database.*) catch {};
            database.close() catch {};
            self.sqlite_database = null;
        }
        if (self.sqlite_database_path) |path| {
            self.allocator.free(path);
            self.sqlite_database_path = null;
        }
        self.markStarting(.sqlite, true, true);
        self.sqlite_database = try self.openSqlite();
        self.markHealthy(.sqlite);
    }

    fn openSqlite(self: *ManagedRuntime) !sqlite_adapter.Database {
        const database_path = if (self.external_config) |external|
            try self.allocator.dupe(u8, external.sqlite_path)
        else blk: {
            const sqlite_dir = try std.fs.path.join(self.allocator, &.{ self.config.data_root, sqlite_dir_name });
            defer self.allocator.free(sqlite_dir);
            try std.fs.cwd().makePath(sqlite_dir);
            break :blk try std.fs.path.join(self.allocator, &.{ sqlite_dir, sqlite_database_file_name });
        };
        errdefer self.allocator.free(database_path);
        var database = try sqlite_adapter.Database.open(self.allocator, .{
            .data_root = self.config.data_root,
            .database_path = database_path,
        });
        errdefer database.close() catch {};
        try database.applyMigrations(self.allocator);
        try database.healthProbe();
        self.sqlite_database_path = database_path;
        return database;
    }

    fn retryTigerBeetle(self: *ManagedRuntime) !void {
        if (self.external_config != null) {
            self.closeTigerBeetleClient();
        } else {
            self.stopTigerBeetle();
        }
        self.markStarting(.tigerbeetle, true, true);
        try self.startTigerBeetle();
        self.markHealthy(.tigerbeetle);
    }

    fn startTigerBeetle(self: *ManagedRuntime) !void {
        if (self.external_config) |external| {
            var client = try api_tigerbeetle.Client.init(self.allocator, .{ .address = external.tigerbeetle_address });
            errdefer client.deinit() catch self.allocator.destroy(client);
            _ = try client.healthProbe();
            self.tigerbeetle_client = client;
            return;
        }

        const binary_path = try std.fs.path.join(self.allocator, &.{ self.config.runtime_root, "tigerbeetle", "tigerbeetle.exe" });
        defer self.allocator.free(binary_path);
        try tigerbeetle.validateRuntimeBinary(binary_path);
        const tigerbeetle_root = try std.fs.path.join(self.allocator, &.{ self.config.data_root, "tigerbeetle" });
        defer self.allocator.free(tigerbeetle_root);
        try std.fs.cwd().makePath(tigerbeetle_root);

        var reservation = try tigerbeetle.reserveDynamicAddress(self.allocator);
        var reservation_released = false;
        defer if (!reservation_released) reservation.reservation.release();
        defer self.allocator.free(reservation.address);
        const port = reservation.reservation.port;

        var plan = try tigerbeetle.makeStartupPlan(self.allocator, .{
            .binary_path = binary_path,
            .data_root = tigerbeetle_root,
        }, port, null);
        defer plan.deinit(self.allocator);

        if (plan.format_command) |format_command| {
            try runCommand(self.allocator, format_command.argv);
        }

        const containment = try platform.initKillOnCloseContainment();
        errdefer platform.closeContainment(containment);
        reservation.reservation.release();
        reservation_released = true;
        const process = try platform.spawnContained(containment, self.allocator, plan.start_command.argv);
        errdefer _ = platform.killContained(process) catch {};

        const address = try self.allocator.dupe(u8, plan.address);
        errdefer self.allocator.free(address);

        try tigerbeetle.waitForListening(address, tigerbeetle.request_timeout_ms);
        tigerbeetle.sleepMs(3_000);
        switch (tigerbeetle.probeStatus(address, plan.cluster_id)) {
            .healthy => {},
            .unavailable => return error.TigerBeetleUnavailable,
            .timeout => return error.TigerBeetleTimeout,
            .native_shutdown_timeout => return error.NativeShutdownTimeout,
            .internal_error => return error.TigerBeetleInternalError,
        }

        self.tigerbeetle_containment = containment;
        self.tigerbeetle_process = process;
        self.tigerbeetle_address = address;
        self.tigerbeetle_cluster_id = plan.cluster_id;
    }

    fn stopTigerBeetle(self: *ManagedRuntime) void {
        if (self.tigerbeetle_containment) |containment| {
            if (self.tigerbeetle_process) |process| {
                _ = tigerbeetle.shutdownContained(containment, process) catch {};
                self.tigerbeetle_process = null;
            }
            platform.closeContainment(containment);
            self.tigerbeetle_containment = null;
        }
        if (self.tigerbeetle_address) |address| {
            self.allocator.free(address);
            self.tigerbeetle_address = null;
        }
        self.tigerbeetle_cluster_id = null;
    }

    fn closeTigerBeetleClient(self: *ManagedRuntime) void {
        if (self.tigerbeetle_client) |client| {
            client.deinit() catch {};
            self.tigerbeetle_client = null;
        }
    }

    fn validateManagedAssets(self: *ManagedRuntime) !void {
        const binary_path = try std.fs.path.join(self.allocator, &.{ self.config.runtime_root, "tigerbeetle", "tigerbeetle.exe" });
        defer self.allocator.free(binary_path);
        try tigerbeetle.validateRuntimeBinary(binary_path);
    }

    fn markStarting(self: *ManagedRuntime, component: status.ComponentId, retrying: bool, retry_active: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const target = self.snapshot_value.component(component);
        target.state = if (retrying) .retrying else .starting;
        target.attempt_count += 1;
        target.retry_active = retry_active;
        target.diagnostic = null;
        self.refreshOverallLocked();
    }

    fn markHealthy(self: *ManagedRuntime, component: status.ComponentId) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const target = self.snapshot_value.component(component);
        target.state = .healthy;
        target.retry_active = false;
        target.diagnostic = null;
        self.refreshOverallLocked();
    }

    fn markUnhealthy(self: *ManagedRuntime, component: status.ComponentId, err: anyerror) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const target = self.snapshot_value.component(component);
        target.state = .unhealthy;
        target.retry_active = false;
        target.diagnostic = sanitizedError(component, err);
        self.refreshOverallLocked();
    }

    fn markAttemptFailed(self: *ManagedRuntime, component: status.ComponentId, err: anyerror, will_retry: bool) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const target = self.snapshot_value.component(component);
        target.state = if (will_retry) .retrying else .unhealthy;
        target.retry_active = will_retry;
        target.diagnostic = sanitizedError(component, err);
        self.refreshOverallLocked();
    }

    fn markStartupFailure(self: *ManagedRuntime, err: anyerror) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.snapshot_value.sqlite.state != .healthy) {
            self.snapshot_value.sqlite.state = .unhealthy;
            self.snapshot_value.sqlite.retry_active = false;
            self.snapshot_value.sqlite.diagnostic = sanitizedError(.sqlite, err);
        }
        if (self.snapshot_value.tigerbeetle.state != .healthy) {
            self.snapshot_value.tigerbeetle.state = .unhealthy;
            self.snapshot_value.tigerbeetle.retry_active = false;
            self.snapshot_value.tigerbeetle.diagnostic = sanitizedError(.tigerbeetle, err);
        }
        self.refreshOverallLocked();
    }

    fn isShutdownStarted(self: *ManagedRuntime) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.shutdown_started;
    }

    fn joinStartupThread(self: *ManagedRuntime) void {
        if (self.startup_thread) |thread| {
            thread.join();
            self.startup_thread = null;
        }
    }

    fn refreshOverall(self: *ManagedRuntime) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.refreshOverallLocked();
    }

    fn refreshOverallLocked(self: *ManagedRuntime) void {
        if (self.snapshot_value.overall_state == .stopping) return;
        if (self.snapshot_value.sqlite.state == .healthy and self.snapshot_value.tigerbeetle.state == .healthy) {
            self.snapshot_value.overall_state = .ready;
        } else if (self.snapshot_value.sqlite.state == .unhealthy or self.snapshot_value.tigerbeetle.state == .unhealthy) {
            self.snapshot_value.overall_state = .degraded;
        } else {
            self.snapshot_value.overall_state = .starting;
        }
    }

    fn recordIdleMemory(self: *ManagedRuntime) !void {
        _ = self;
        const bytes = currentProcessMemoryBytes();
        if (bytes > idle_memory_budget_bytes) return error.IdleMemoryBudgetExceeded;
    }

    fn ensureExternalSqliteParent(self: *ManagedRuntime) !void {
        const external = self.external_config orelse return;
        const parent = std.fs.path.dirname(external.sqlite_path) orelse return error.InvalidDatabasePath;
        try std.fs.cwd().makePath(parent);
    }
};

pub const RuntimeActions = struct {
    retry_sqlite: bool = false,
    retry_tigerbeetle: bool = false,
    shutdown: bool = false,
};

pub fn retryDelayMs(component: status.ComponentId, attempt_index: usize) ?u32 {
    return switch (component) {
        .sqlite => if (attempt_index < startup_retry_delays_ms.len) startup_retry_delays_ms[attempt_index] else null,
        .tigerbeetle => tigerbeetle.retryDelayMs(attempt_index),
    };
}

pub fn sanitizedError(component: status.ComponentId, err: anyerror) status.SanitizedError {
    const code: status.ErrorCode = switch (component) {
        .sqlite => switch (sqlite_adapter.mapNativeError(err)) {
            .sqlite_busy => .sqlite_busy,
            .sqlite_timeout => .sqlite_timeout,
            .sqlite_unavailable => .sqlite_unavailable,
            .internal_error => .internal_error,
        },
        .tigerbeetle => switch (err) {
            error.NativeShutdownTimeout => .native_shutdown_timeout,
            error.TigerBeetleTimeout => .tigerbeetle_timeout,
            else => .tigerbeetle_unavailable,
        },
    };
    return .{ .code = code, .message = status.messageFor(code) };
}

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code == 0) return else return error.CommandFailed,
        else => return error.CommandFailed,
    }
}

fn checkpointSqlite(database: sqlite_adapter.Database) !void {
    try database.healthProbe();
}

fn currentProcessMemoryBytes() usize {
    if (builtin.os.tag == .windows) {
        var counters: ProcessMemoryCounters = .{
            .cb = @sizeOf(ProcessMemoryCounters),
            .page_fault_count = 0,
            .peak_working_set_size = 0,
            .working_set_size = 0,
            .quota_peak_paged_pool_usage = 0,
            .quota_paged_pool_usage = 0,
            .quota_peak_non_paged_pool_usage = 0,
            .quota_non_paged_pool_usage = 0,
            .pagefile_usage = 0,
            .peak_pagefile_usage = 0,
        };
        if (K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, @sizeOf(ProcessMemoryCounters)) != 0) {
            return counters.working_set_size;
        }
    }
    return 0;
}

fn sleepMs(milliseconds: u32) void {
    std.Thread.sleep(@as(u64, milliseconds) * std.time.ns_per_ms);
}

const ProcessMemoryCounters = extern struct {
    cb: u32,
    page_fault_count: u32,
    peak_working_set_size: usize,
    working_set_size: usize,
    quota_peak_paged_pool_usage: usize,
    quota_paged_pool_usage: usize,
    quota_peak_non_paged_pool_usage: usize,
    quota_non_paged_pool_usage: usize,
    pagefile_usage: usize,
    peak_pagefile_usage: usize,
};

extern "kernel32" fn GetCurrentProcess() callconv(.winapi) usize;
extern "kernel32" fn K32GetProcessMemoryInfo(process: usize, counters: *ProcessMemoryCounters, size: u32) callconv(.winapi) i32;

pub fn selfTest() !void {
    if (restart_budget_count != 3) return error.InvalidSupervisorBudget;
    if (initial_readiness_timeout_ms != 60_000) return error.InvalidSupervisorBudget;
    if (idle_memory_budget_bytes != 500 * 1024 * 1024) return error.InvalidSupervisorBudget;
    if (native_shutdown_timeout_exit_code != 7) return error.InvalidSupervisorBudget;
    if (sqlite_close_checkpoint_timeout_ms != 10_000) return error.InvalidSupervisorBudget;
    try std.testing.expectEqual(@as(?u32, 1_000), retryDelayMs(.sqlite, 0));
    try std.testing.expectEqual(@as(?u32, 1_000), retryDelayMs(.tigerbeetle, 0));
    try std.testing.expectEqual(status.ErrorCode.sqlite_busy, sanitizedError(.sqlite, error.SqliteBusy).code);
    try std.testing.expectEqual(status.ErrorCode.native_shutdown_timeout, sanitizedError(.tigerbeetle, error.NativeShutdownTimeout).code);
}

test "IMAGE-001 external runtime opens SQLite path without managed assets" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("data");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const data_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "data" });
    defer std.testing.allocator.free(data_root);
    const sqlite_path = try std.fs.path.join(std.testing.allocator, &.{ data_root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(sqlite_path);

    var runtime = ManagedRuntime.init(std.testing.allocator, .{
        .runtime_root = data_root,
        .data_root = data_root,
    });
    runtime.external_config = .{
        .sqlite_path = sqlite_path,
        .tigerbeetle_address = "127.0.0.1:3000",
    };
    defer {
        runtime.external_config = null;
        runtime.deinit();
    }

    try runtime.ensureExternalSqliteParent();
    runtime.sqlite_database = try runtime.openSqlite();
    try runtime.sqlite_database.?.applyMigrations(std.testing.allocator);
    try runtime.sqlite_database.?.healthProbe();
    runtime.markHealthy(.sqlite);
    const snapshot = runtime.snapshot();
    try std.testing.expectEqual(status.ComponentState.healthy, snapshot.sqlite.state);
    try std.testing.expectEqual(status.ComponentState.starting, snapshot.tigerbeetle.state);
}

test "IMAGE-001 external runtime reaches ready without managed process handles" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("data");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const data_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "data" });
    defer std.testing.allocator.free(data_root);
    const sqlite_path = try std.fs.path.join(std.testing.allocator, &.{ data_root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(sqlite_path);

    var runtime = ManagedRuntime.init(std.testing.allocator, .{
        .runtime_root = data_root,
        .data_root = data_root,
    });
    runtime.external_config = .{
        .sqlite_path = try std.testing.allocator.dupe(u8, sqlite_path),
        .tigerbeetle_address = try std.testing.allocator.dupe(u8, "127.0.0.1:3000"),
    };
    defer runtime.deinit();

    try runtime.ensureExternalSqliteParent();
    runtime.sqlite_database = try runtime.openSqlite();
    runtime.markHealthy(.sqlite);
    runtime.markHealthy(.tigerbeetle);

    const snapshot = runtime.snapshot();
    try std.testing.expect(snapshot.isReady());
    try std.testing.expect(runtime.tigerbeetle_containment == null);
    try std.testing.expect(runtime.tigerbeetle_process == null);
    try std.testing.expect(runtime.tigerbeetle_address == null);
    try std.testing.expect(runtime.tigerbeetle_cluster_id == null);
}

test "IMAGE-001 external TigerBeetle retry degrades without managed spawn" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("data");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const data_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "data" });
    defer std.testing.allocator.free(data_root);
    const sqlite_path = try std.fs.path.join(std.testing.allocator, &.{ data_root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(sqlite_path);

    var runtime = ManagedRuntime.init(std.testing.allocator, .{
        .runtime_root = data_root,
        .data_root = data_root,
    });
    runtime.external_config = .{
        .sqlite_path = try std.testing.allocator.dupe(u8, sqlite_path),
        .tigerbeetle_address = try std.testing.allocator.dupe(u8, "127.0.0.1 invalid"),
    };
    defer runtime.deinit();

    runtime.markHealthy(.sqlite);
    runtime.runRetry(.tigerbeetle);

    const snapshot = runtime.snapshot();
    try std.testing.expectEqual(status.OverallState.degraded, snapshot.overall_state);
    try std.testing.expectEqual(status.ComponentState.unhealthy, snapshot.tigerbeetle.state);
    try std.testing.expectEqual(@as(u32, 1), snapshot.tigerbeetle.attempt_count);
    try std.testing.expect(!snapshot.tigerbeetle.retry_active);
    try std.testing.expect(snapshot.tigerbeetle.diagnostic != null);
    try std.testing.expect(runtime.tigerbeetle_client == null);
    try std.testing.expect(runtime.tigerbeetle_containment == null);
    try std.testing.expect(runtime.tigerbeetle_process == null);
    try std.testing.expect(runtime.tigerbeetle_address == null);
}

test "IMAGE-001 external shutdown clears status and owned config" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("data");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const data_root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "data" });
    defer std.testing.allocator.free(data_root);
    const sqlite_path = try std.fs.path.join(std.testing.allocator, &.{ data_root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(sqlite_path);

    var runtime = ManagedRuntime.init(std.testing.allocator, .{
        .runtime_root = data_root,
        .data_root = data_root,
    });
    runtime.external_config = .{
        .sqlite_path = try std.testing.allocator.dupe(u8, sqlite_path),
        .tigerbeetle_address = try std.testing.allocator.dupe(u8, "127.0.0.1:3000"),
    };

    try runtime.ensureExternalSqliteParent();
    runtime.sqlite_database = try runtime.openSqlite();
    runtime.markHealthy(.sqlite);
    runtime.markHealthy(.tigerbeetle);
    runtime.shutdown();

    const snapshot = runtime.snapshot();
    try std.testing.expectEqual(status.ComponentState.stopped, snapshot.sqlite.state);
    try std.testing.expectEqual(status.ComponentState.stopped, snapshot.tigerbeetle.state);
    try std.testing.expect(runtime.external_config == null);
    try std.testing.expect(runtime.sqlite_database == null);
    try std.testing.expect(runtime.sqlite_database_path == null);
    try std.testing.expect(runtime.tigerbeetle_client == null);
    try std.testing.expect(runtime.tigerbeetle_containment == null);
    try std.testing.expect(runtime.tigerbeetle_process == null);
}

test "RUNTIME-004 supervisor constants and sanitized states are stable" {
    try selfTest();
}
