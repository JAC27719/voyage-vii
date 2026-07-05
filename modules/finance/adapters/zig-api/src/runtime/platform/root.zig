const std = @import("std");
const builtin = @import("builtin");

pub const current_target = "x86_64-pc-windows-msvc";
pub const lock_file_name = "voyage-vii.lock";

pub const PlatformError = error{
    PathEscapesRoot,
    PathIsAbsolute,
    PathContainsParentTraversal,
    DataRootLocked,
    UnsupportedPlatform,
};

pub const CanonicalPath = struct {
    bytes: []u8,

    pub fn deinit(self: CanonicalPath, allocator: std.mem.Allocator) void {
        allocator.free(self.bytes);
    }
};

pub const RootLock = struct {
    file: std.fs.File,

    pub fn release(self: *RootLock) void {
        self.file.close();
    }
};

pub const LoopbackReservation = struct {
    server: std.net.Server,
    port: u16,

    pub fn release(self: *LoopbackReservation) void {
        self.server.deinit();
    }
};

const ContainmentState = struct {
    handle_value: usize,
};

const ContainedProcessState = struct {
    allocator: std.mem.Allocator,
    child: std.process.Child,
};

pub const ProcessContainment = *anyopaque;
pub const ContainedProcess = *anyopaque;

pub fn initKillOnCloseContainment() PlatformError!ProcessContainment {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    return windowsCreateKillOnCloseJob();
}

pub fn spawnContained(containment: ProcessContainment, allocator: std.mem.Allocator, argv: []const []const u8) !ContainedProcess {
    const state = try allocator.create(ContainedProcessState);
    errdefer allocator.destroy(state);
    state.* = .{
        .allocator = allocator,
        .child = std.process.Child.init(argv, allocator),
    };
    state.child.stdin_behavior = .Ignore;
    state.child.stdout_behavior = .Ignore;
    state.child.stderr_behavior = .Ignore;
    try state.child.spawn();
    errdefer _ = state.child.kill() catch {};
    try assignSpawnedChild(containment, state);
    return state;
}

pub fn waitContained(process: ContainedProcess) !std.process.Child.Term {
    const state = containedProcessState(process);
    const term = try state.child.wait();
    const allocator = state.allocator;
    allocator.destroy(state);
    return term;
}

pub fn killContained(process: ContainedProcess) !std.process.Child.Term {
    const state = containedProcessState(process);
    const term = try state.child.kill();
    const allocator = state.allocator;
    allocator.destroy(state);
    return term;
}

pub fn terminateContainment(containment: ProcessContainment, exit_code: u32) void {
    const state = containmentState(containment);
    if (builtin.os.tag == .windows and state.handle_value != 0) {
        _ = windowsTerminateJob(state.handle_value, exit_code);
    }
}

pub fn closeContainment(containment: ProcessContainment) void {
    const state = containmentState(containment);
    if (builtin.os.tag == .windows and state.handle_value != 0) {
        _ = windowsCloseHandle(state.handle_value);
        state.handle_value = 0;
    }
    std.heap.page_allocator.destroy(state);
}

fn assignSpawnedChild(containment: ProcessContainment, process: *const ContainedProcessState) PlatformError!void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    const state = containmentState(containment);
    if (state.handle_value == 0) return error.UnsupportedPlatform;
    if (windowsAssignProcess(state.handle_value, @intFromPtr(process.child.id)) == 0) return error.UnsupportedPlatform;
}

fn containmentState(containment: ProcessContainment) *ContainmentState {
    return @ptrCast(@alignCast(containment));
}

fn containedProcessState(process: ContainedProcess) *ContainedProcessState {
    return @ptrCast(@alignCast(process));
}

pub fn rejectRelativeEscape(path: []const u8) PlatformError!void {
    if (std.fs.path.isAbsolute(path)) return error.PathIsAbsolute;
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return error.PathContainsParentTraversal;
    }
}

pub fn canonicalizeInside(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    child_path: []const u8,
) !CanonicalPath {
    try rejectRelativeEscape(child_path);
    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();

    const root_real = try std.fs.cwd().realpathAlloc(allocator, root_path);
    defer allocator.free(root_real);
    const child_real = try root_dir.realpathAlloc(allocator, child_path);
    errdefer allocator.free(child_real);

    if (!isWithinRoot(root_real, child_real)) return error.PathEscapesRoot;
    return .{ .bytes = child_real };
}

pub fn acquireRootLock(root_path: []const u8) !RootLock {
    var root_dir = try std.fs.cwd().openDir(root_path, .{});
    defer root_dir.close();
    const file = root_dir.createFile(lock_file_name, .{
        .read = true,
        .truncate = false,
        .lock = .exclusive,
        .lock_nonblocking = true,
    }) catch |err| switch (err) {
        error.WouldBlock => return error.DataRootLocked,
        else => return err,
    };
    return .{ .file = file };
}

pub fn reserveLoopbackPort() !LoopbackReservation {
    const address = try std.net.Address.parseIp4("127.0.0.1", 0);
    var server = try address.listen(.{
        .reuse_address = false,
    });
    errdefer server.deinit();
    return .{ .server = server, .port = server.listen_address.getPort() };
}

fn isWithinRoot(root_real: []const u8, child_real: []const u8) bool {
    if (std.mem.eql(u8, root_real, child_real)) return true;
    if (!std.mem.startsWith(u8, child_real, root_real)) return false;
    const suffix = child_real[root_real.len..];
    return suffix.len > 0 and (suffix[0] == '/' or suffix[0] == '\\');
}

fn windowsCreateKillOnCloseJob() PlatformError!ProcessContainment {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    const handle = windowsCreateJobObject(null, null);
    if (handle == 0) return error.UnsupportedPlatform;
    var info: JobObjectExtendedLimitInformation = .{
        .basic_limit_information = .{
            .per_process_user_time_limit = 0,
            .per_job_user_time_limit = 0,
            .limit_flags = job_object_limit_kill_on_job_close,
            .minimum_working_set_size = 0,
            .maximum_working_set_size = 0,
            .active_process_limit = 0,
            .affinity = 0,
            .priority_class = 0,
            .scheduling_class = 0,
        },
        .io_info = .{
            .read_operation_count = 0,
            .write_operation_count = 0,
            .other_operation_count = 0,
            .read_transfer_count = 0,
            .write_transfer_count = 0,
            .other_transfer_count = 0,
        },
        .process_memory_limit = 0,
        .job_memory_limit = 0,
        .peak_process_memory_used = 0,
        .peak_job_memory_used = 0,
    };
    const ok = windowsSetInformationJobObject(
        handle,
        job_object_extended_limit_information,
        &info,
        @sizeOf(JobObjectExtendedLimitInformation),
    );
    if (ok == 0) {
        _ = windowsCloseHandle(handle);
        return error.UnsupportedPlatform;
    }
    const state = std.heap.page_allocator.create(ContainmentState) catch return error.UnsupportedPlatform;
    state.* = .{ .handle_value = handle };
    return state;
}

const job_object_extended_limit_information: u32 = 9;
const job_object_limit_kill_on_job_close: u32 = 0x00002000;

const BasicLimitInformation = extern struct {
    per_process_user_time_limit: i64,
    per_job_user_time_limit: i64,
    limit_flags: u32,
    minimum_working_set_size: usize,
    maximum_working_set_size: usize,
    active_process_limit: u32,
    affinity: usize,
    priority_class: u32,
    scheduling_class: u32,
};

const IoCounters = extern struct {
    read_operation_count: u64,
    write_operation_count: u64,
    other_operation_count: u64,
    read_transfer_count: u64,
    write_transfer_count: u64,
    other_transfer_count: u64,
};

const JobObjectExtendedLimitInformation = extern struct {
    basic_limit_information: BasicLimitInformation,
    io_info: IoCounters,
    process_memory_limit: usize,
    job_memory_limit: usize,
    peak_process_memory_used: usize,
    peak_job_memory_used: usize,
};

extern "kernel32" fn CreateJobObjectW(attributes: ?*anyopaque, name: ?[*:0]const u16) callconv(.winapi) usize;
extern "kernel32" fn SetInformationJobObject(job: usize, class: u32, info: *const JobObjectExtendedLimitInformation, length: u32) callconv(.winapi) i32;
extern "kernel32" fn AssignProcessToJobObject(job: usize, process: usize) callconv(.winapi) i32;
extern "kernel32" fn TerminateJobObject(job: usize, exit_code: u32) callconv(.winapi) i32;
extern "kernel32" fn CloseHandle(handle: usize) callconv(.winapi) i32;

fn windowsCreateJobObject(attributes: ?*anyopaque, name: ?[*:0]const u16) usize {
    if (builtin.os.tag != .windows) return 0;
    return CreateJobObjectW(attributes, name);
}

fn windowsSetInformationJobObject(job: usize, class: u32, info: *const JobObjectExtendedLimitInformation, length: u32) i32 {
    if (builtin.os.tag != .windows) return 0;
    return SetInformationJobObject(job, class, info, length);
}

fn windowsAssignProcess(job: usize, process: usize) i32 {
    if (builtin.os.tag != .windows) return 0;
    return AssignProcessToJobObject(job, process);
}

fn windowsTerminateJob(job: usize, exit_code: u32) i32 {
    if (builtin.os.tag != .windows) return 0;
    return TerminateJobObject(job, exit_code);
}

fn windowsCloseHandle(handle: usize) i32 {
    if (builtin.os.tag != .windows) return 0;
    return CloseHandle(handle);
}

pub fn selfTest() !void {
    try rejectRelativeEscape("postgresql/data");
    try expectPlatformError(error.PathContainsParentTraversal, rejectRelativeEscape("../escape"));
    try expectPlatformError(error.PathContainsParentTraversal, rejectRelativeEscape("safe/../escape"));

    if (builtin.os.tag == .windows) {
        const containment = try initKillOnCloseContainment();
        defer closeContainment(containment);
        if (containmentState(containment).handle_value == 0) return error.SelfTestFailed;
    } else {
        try expectPlatformError(error.UnsupportedPlatform, initKillOnCloseContainment());
    }
}

fn expectPlatformError(expected: anyerror, actual: anytype) !void {
    if (actual) |_| return error.SelfTestFailed else |err| {
        if (err == expected) return;
        return err;
    }
}

test "runtime platform canonicalizes paths and rejects symlink escapes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root/child");
    try tmp.dir.makePath("outside");
    try tmp.dir.writeFile(.{ .sub_path = "root/child/file.txt", .data = "ok" });
    try tmp.dir.writeFile(.{ .sub_path = "outside/file.txt", .data = "escape" });

    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "root" });
    defer std.testing.allocator.free(root_path);
    const outside_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "outside" });
    defer std.testing.allocator.free(outside_path);

    const canonical = try canonicalizeInside(std.testing.allocator, root_path, "child/file.txt");
    defer canonical.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, canonical.bytes, "file.txt"));

    if (tmp.dir.symLink(outside_path, "root/link", .{ .is_directory = true })) {
        try std.testing.expectError(
            error.PathEscapesRoot,
            canonicalizeInside(std.testing.allocator, root_path, "link/file.txt"),
        );
    } else |err| switch (err) {
        error.AccessDenied, error.FileNotFound => {},
        else => return err,
    }

    var first_lock = try acquireRootLock(root_path);
    defer first_lock.release();
    try std.testing.expectError(error.DataRootLocked, acquireRootLock(root_path));

    var reservation = try reserveLoopbackPort();
    defer reservation.release();
    try std.testing.expect(reservation.port > 0);
}

test "runtime platform Windows job object contains children" {
    if (builtin.os.tag == .windows) {
        const containment = try initKillOnCloseContainment();
        try std.testing.expect(containmentState(containment).handle_value != 0);
        const child = try spawnContained(
            containment,
            std.testing.allocator,
            &.{ "powershell", "-NoProfile", "-Command", "Start-Sleep -Seconds 30" },
        );
        errdefer _ = killContained(child) catch {};
        closeContainment(containment);
        const term = try waitContained(child);
        try std.testing.expect(term == .Exited);
    } else {
        try std.testing.expectError(error.UnsupportedPlatform, initKillOnCloseContainment());
    }
}
