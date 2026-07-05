const std = @import("std");
const sqlite = @import("sqlite_adapter");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const component_id = sqlite.component_id;
pub const database_dir_name = "sqlite";
pub const database_file_name = "voyage-vii.sqlite3";
pub const wal_file_name = database_file_name ++ "-wal";
pub const shm_file_name = database_file_name ++ "-shm";
pub const open_timeout_ms = sqlite.open_timeout_ms;
pub const busy_timeout_ms: u32 = @intCast(sqlite.busy_timeout_ms);
pub const query_timeout_ms = sqlite.query_timeout_ms;
pub const close_checkpoint_timeout_ms: u32 = 10_000;
pub const startup_retry_delays_ms = [_]u32{ 1_000, 2_000, 4_000 };

pub const LifecycleError = error{
    DataRootMustBeAbsolute,
    DataRootContainsParentTraversal,
    DataRootUnavailable,
    InvalidDataRoot,
    PathEscapesRoot,
    CheckpointFailed,
    FileSystem,
    NotSupported,
    UnrecognizedVolume,
} || sqlite.AdapterError ||
    std.fs.File.OpenError ||
    std.fs.File.ReadError ||
    std.fs.File.WriteError ||
    std.fs.Dir.MakeError ||
    std.fs.File.StatError ||
    std.mem.Allocator.Error;

pub const RootState = enum {
    pristine,
    initialized,
    invalid,
};

pub const ComponentState = enum {
    starting,
    healthy,
    retrying,
    unhealthy,
    stopping,
    stopped,
};

pub const SanitizedError = struct {
    code: sqlite.ErrorCode,
    message: []const u8,
};

pub const ComponentStatus = struct {
    id: []const u8 = component_id,
    display_name: []const u8 = "SQLite",
    state: ComponentState = .starting,
    attempt_count: u32 = 0,
    last_error: ?SanitizedError = null,
};

pub const ManagedPaths = struct {
    data_root: []u8,
    sqlite_dir: []u8,
    database: []u8,
    wal: []u8,
    shm: []u8,

    pub fn deinit(self: ManagedPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.data_root);
        allocator.free(self.sqlite_dir);
        allocator.free(self.database);
        allocator.free(self.wal);
        allocator.free(self.shm);
    }
};

pub const ManagedDatabase = struct {
    allocator: std.mem.Allocator,
    paths: ManagedPaths,
    database: ?sqlite.Database,
    status: ComponentStatus,

    pub fn probe(self: *ManagedDatabase) !void {
        if (self.database) |database| {
            try database.healthProbe();
            self.status.state = .healthy;
            self.status.last_error = null;
        } else {
            self.status.state = .unhealthy;
            self.status.last_error = sanitizedError(error.SqliteUnavailable);
            return error.SqliteUnavailable;
        }
    }

    pub fn checkpointAndClose(self: *ManagedDatabase) !void {
        self.status.state = .stopping;
        if (self.database) |*database| {
            try checkpointTruncate(database.*);
            try database.close();
            self.database = null;
        }
        self.status.state = .stopped;
        self.status.last_error = null;
    }

    pub fn deinit(self: *ManagedDatabase) void {
        if (self.database) |*database| {
            database.close() catch {};
            self.database = null;
        }
        self.paths.deinit(self.allocator);
    }
};

pub fn planManagedPaths(allocator: std.mem.Allocator, data_root: []const u8) LifecycleError!ManagedPaths {
    try validateDataRootInput(data_root);
    const root_real = std.fs.cwd().realpathAlloc(allocator, data_root) catch return error.DataRootUnavailable;
    errdefer allocator.free(root_real);

    const sqlite_dir = try std.fs.path.join(allocator, &.{ root_real, database_dir_name });
    errdefer allocator.free(sqlite_dir);
    const database = try std.fs.path.join(allocator, &.{ sqlite_dir, database_file_name });
    errdefer allocator.free(database);
    const wal = try std.fs.path.join(allocator, &.{ sqlite_dir, wal_file_name });
    errdefer allocator.free(wal);
    const shm = try std.fs.path.join(allocator, &.{ sqlite_dir, shm_file_name });
    errdefer allocator.free(shm);

    if (!isWithinRoot(root_real, sqlite_dir) or
        !isWithinRoot(root_real, database) or
        !isWithinRoot(root_real, wal) or
        !isWithinRoot(root_real, shm))
    {
        return error.PathEscapesRoot;
    }

    return .{
        .data_root = root_real,
        .sqlite_dir = sqlite_dir,
        .database = database,
        .wal = wal,
        .shm = shm,
    };
}

pub fn inspectDataRoot(allocator: std.mem.Allocator, data_root: []const u8) LifecycleError!RootState {
    const paths = try planManagedPaths(allocator, data_root);
    defer paths.deinit(allocator);

    var sqlite_dir = std.fs.cwd().openDir(paths.sqlite_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => return .pristine,
        error.NotDir => return .invalid,
        else => return err,
    };
    sqlite_dir.close();

    const database_exists = fileExists(paths.database) catch return .invalid;
    const wal_exists = fileExists(paths.wal) catch return .invalid;
    const shm_exists = fileExists(paths.shm) catch return .invalid;
    if (database_exists) return .initialized;
    if (wal_exists or shm_exists) return .invalid;

    var dir = try std.fs.cwd().openDir(paths.sqlite_dir, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (std.mem.eql(u8, entry.name, database_file_name) or
            std.mem.eql(u8, entry.name, wal_file_name) or
            std.mem.eql(u8, entry.name, shm_file_name))
        {
            continue;
        }
        return .invalid;
    }
    return .pristine;
}

pub fn openApplyProbe(allocator: std.mem.Allocator, data_root: []const u8) LifecycleError!ManagedDatabase {
    return openApplyProbeWithSleeper(allocator, data_root, sleepMs);
}

pub fn openApplyProbeWithSleeper(
    allocator: std.mem.Allocator,
    data_root: []const u8,
    sleeper: *const fn (u32) void,
) LifecycleError!ManagedDatabase {
    const root_state = try inspectDataRoot(allocator, data_root);
    if (root_state == .invalid) return error.InvalidDataRoot;

    var paths = try planManagedPaths(allocator, data_root);
    errdefer paths.deinit(allocator);
    try std.fs.cwd().makePath(paths.sqlite_dir);

    var status = ComponentStatus{ .state = .starting };
    var attempt: u32 = 0;
    var last_error: LifecycleError = error.SqliteUnavailable;
    while (attempt <= startup_retry_delays_ms.len) : (attempt += 1) {
        if (attempt > 0) {
            status.state = .retrying;
            sleeper(startup_retry_delays_ms[attempt - 1]);
        }
        status.attempt_count = attempt + 1;

        var database = sqlite.Database.open(allocator, .{
            .data_root = paths.data_root,
            .database_path = paths.database,
        }) catch |err| {
            last_error = err;
            status.last_error = sanitizedError(err);
            if (!isStartupRetriable(err)) break;
            continue;
        };
        var keep_database = false;
        defer if (!keep_database) database.close() catch {};

        database.applyMigrations(allocator) catch |err| {
            last_error = err;
            status.last_error = sanitizedError(err);
            if (!isStartupRetriable(err)) return err;
            continue;
        };
        database.healthProbe() catch |err| {
            last_error = err;
            status.last_error = sanitizedError(err);
            if (!isStartupRetriable(err)) return err;
            continue;
        };

        status.state = .healthy;
        status.last_error = null;
        keep_database = true;
        return .{
            .allocator = allocator,
            .paths = paths,
            .database = database,
            .status = status,
        };
    }

    status.state = .unhealthy;
    status.last_error = sanitizedError(last_error);
    return last_error;
}

pub fn checkpointTruncate(database: sqlite.Database) LifecycleError!void {
    var log_frames: c_int = 0;
    var checkpointed_frames: c_int = 0;
    const rc = c.sqlite3_wal_checkpoint_v2(
        @ptrCast(database.handle),
        null,
        c.SQLITE_CHECKPOINT_TRUNCATE,
        &log_frames,
        &checkpointed_frames,
    );
    if (rc != c.SQLITE_OK) return error.CheckpointFailed;
}

pub fn sanitizedError(err: anyerror) SanitizedError {
    const code = sqlite.mapNativeError(err);
    return .{
        .code = code,
        .message = switch (code) {
            .sqlite_busy => "SQLite is busy.",
            .sqlite_timeout => "SQLite operation timed out.",
            .sqlite_unavailable => "SQLite is unavailable.",
            .internal_error => "SQLite runtime failed.",
        },
    };
}

pub fn containsLeakage(value: []const u8) bool {
    return sqlite.containsSecretLikeText(value) or
        std.mem.indexOf(u8, value, ":\\") != null or
        std.ascii.indexOfIgnoreCase(value, "users\\") != null or
        std.ascii.indexOfIgnoreCase(value, "users/") != null;
}

pub fn selfTest() !void {
    if (startup_retry_delays_ms.len != 3) return error.InvalidDataRoot;
    if (startup_retry_delays_ms[0] != 1_000 or
        startup_retry_delays_ms[1] != 2_000 or
        startup_retry_delays_ms[2] != 4_000)
    {
        return error.InvalidDataRoot;
    }
    if (close_checkpoint_timeout_ms != 10_000) return error.InvalidDataRoot;
    if (query_timeout_ms != 3_000) return error.InvalidDataRoot;
    const diagnostic = sanitizedError(error.ChecksumDrift);
    if (containsLeakage(diagnostic.message)) return error.InvalidDataRoot;
}

fn validateDataRootInput(data_root: []const u8) LifecycleError!void {
    if (!std.fs.path.isAbsolute(data_root)) return error.DataRootMustBeAbsolute;
    var it = std.mem.tokenizeAny(u8, data_root, "/\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return error.DataRootContainsParentTraversal;
    }
}

fn fileExists(path: []const u8) !bool {
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return stat.kind == .file;
}

fn isWithinRoot(root_real: []const u8, child_path: []const u8) bool {
    if (std.mem.eql(u8, root_real, child_path)) return true;
    if (!std.mem.startsWith(u8, child_path, root_real)) return false;
    const suffix = child_path[root_real.len..];
    return suffix.len > 0 and (suffix[0] == '/' or suffix[0] == '\\');
}

fn isStartupRetriable(err: anyerror) bool {
    return switch (sqlite.mapNativeError(err)) {
        .sqlite_busy, .sqlite_timeout, .sqlite_unavailable => true,
        .internal_error => false,
    };
}

fn sleepMs(milliseconds: u32) void {
    std.Thread.sleep(@as(u64, milliseconds) * std.time.ns_per_ms);
}
