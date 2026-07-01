const std = @import("std");
const runtime_sqlite = @import("runtime_sqlite");
const sqlite = @import("sqlite_adapter");

const c = @cImport({
    @cInclude("sqlite3.h");
});

var observed_sleeps: [3]u32 = undefined;
var observed_sleep_count: usize = 0;

fn recordSleep(milliseconds: u32) void {
    observed_sleeps[observed_sleep_count] = milliseconds;
    observed_sleep_count += 1;
}

pub fn selfTest() !void {
    try runtime_sqlite.selfTest();
}

test "RUNTIME-002 detects pristine initialized and invalid roots without destructive guessing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root");
    const root = try absoluteTmpPath(&tmp, "root");
    defer std.testing.allocator.free(root);

    try std.testing.expectEqual(runtime_sqlite.RootState.pristine, try runtime_sqlite.inspectDataRoot(std.testing.allocator, root));
    var managed = try runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, root, recordSleep);
    defer managed.deinit();
    try std.testing.expectEqual(runtime_sqlite.RootState.initialized, try runtime_sqlite.inspectDataRoot(std.testing.allocator, root));

    try tmp.dir.makePath("invalid/sqlite");
    try tmp.dir.writeFile(.{ .sub_path = "invalid/sqlite/voyage-vii.sqlite3-wal", .data = "orphan" });
    const invalid = try absoluteTmpPath(&tmp, "invalid");
    defer std.testing.allocator.free(invalid);
    try std.testing.expectEqual(runtime_sqlite.RootState.invalid, try runtime_sqlite.inspectDataRoot(std.testing.allocator, invalid));
    try std.testing.expectError(error.InvalidDataRoot, runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, invalid, recordSleep));
}

test "RUNTIME-002 plans only root-contained database wal and shm paths" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root");
    const root = try absoluteTmpPath(&tmp, "root");
    defer std.testing.allocator.free(root);

    const paths = try runtime_sqlite.planManagedPaths(std.testing.allocator, root);
    defer paths.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.endsWith(u8, paths.sqlite_dir, "sqlite"));
    try std.testing.expect(std.mem.endsWith(u8, paths.database, "sqlite\\voyage-vii.sqlite3") or
        std.mem.endsWith(u8, paths.database, "sqlite/voyage-vii.sqlite3"));
    try std.testing.expect(std.mem.endsWith(u8, paths.wal, "voyage-vii.sqlite3-wal"));
    try std.testing.expect(std.mem.endsWith(u8, paths.shm, "voyage-vii.sqlite3-shm"));
    try std.testing.expect(std.mem.startsWith(u8, paths.database, paths.data_root));

    try std.testing.expectError(error.DataRootMustBeAbsolute, runtime_sqlite.planManagedPaths(std.testing.allocator, "relative/root"));
}

test "RUNTIME-002 opens applies probes and retains managed SQLite" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root");
    const root = try absoluteTmpPath(&tmp, "root");
    defer std.testing.allocator.free(root);

    observed_sleep_count = 0;
    var first = try runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, root, recordSleep);
    try std.testing.expectEqual(runtime_sqlite.ComponentState.healthy, first.status.state);
    try std.testing.expectEqual(@as(u32, 1), first.status.attempt_count);
    try std.testing.expectEqual(@as(usize, 0), observed_sleep_count);
    try first.probe();
    try first.checkpointAndClose();
    try std.testing.expectEqual(runtime_sqlite.ComponentState.stopped, first.status.state);
    first.deinit();

    var retained = try runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, root, recordSleep);
    defer retained.deinit();
    try retained.probe();
    try std.testing.expectEqual(runtime_sqlite.ComponentState.healthy, retained.status.state);
}

test "RUNTIME-002 exposes retry schedule as frozen declarative behavior" {
    try std.testing.expectEqual(@as(usize, 3), runtime_sqlite.startup_retry_delays_ms.len);
    try std.testing.expectEqual(@as(u32, 1_000), runtime_sqlite.startup_retry_delays_ms[0]);
    try std.testing.expectEqual(@as(u32, 2_000), runtime_sqlite.startup_retry_delays_ms[1]);
    try std.testing.expectEqual(@as(u32, 4_000), runtime_sqlite.startup_retry_delays_ms[2]);
    try std.testing.expectEqual(@as(u32, 10_000), runtime_sqlite.close_checkpoint_timeout_ms);
}

test "RUNTIME-002 maps busy and failed migration diagnostics without leaking paths or SQL values" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root");
    const root = try absoluteTmpPath(&tmp, "root");
    defer std.testing.allocator.free(root);

    var managed = try runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, root, recordSleep);
    defer managed.deinit();

    var second = try sqlite.Database.open(std.testing.allocator, .{
        .data_root = managed.paths.data_root,
        .database_path = managed.paths.database,
    });
    defer second.close() catch {};

    try exec(@ptrCast(managed.database.?.handle), "BEGIN IMMEDIATE;");
    defer exec(@ptrCast(managed.database.?.handle), "ROLLBACK;") catch {};
    const busy = busy: {
        exec(@ptrCast(second.handle), "BEGIN IMMEDIATE;") catch |err| break :busy runtime_sqlite.sanitizedError(err);
        return error.ExpectedBusyDatabase;
    };
    try std.testing.expectEqual(sqlite.ErrorCode.sqlite_busy, busy.code);
    try std.testing.expect(!runtime_sqlite.containsLeakage(busy.message));
    try std.testing.expect(runtime_sqlite.containsLeakage("sqlite-path=C:\\Users\\example\\voyage.sqlite3"));
    try std.testing.expect(runtime_sqlite.containsLeakage("SELECT * FROM schema_migrations"));

    try exec(@ptrCast(managed.database.?.handle), "ROLLBACK;");
    try exec(@ptrCast(managed.database.?.handle), "UPDATE schema_migrations SET sha256 = '0000000000000000000000000000000000000000000000000000000000000000' WHERE version = 1;");
    const drift = drift: {
        managed.database.?.applyMigrations(std.testing.allocator) catch |err| break :drift runtime_sqlite.sanitizedError(err);
        return error.ExpectedFailedMigration;
    };
    try std.testing.expectEqual(sqlite.ErrorCode.internal_error, drift.code);
    try std.testing.expect(!runtime_sqlite.containsLeakage(drift.message));
}

test "RUNTIME-002 checkpoint close truncates WAL and is safe to call before forced process exit boundary" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root");
    const root = try absoluteTmpPath(&tmp, "root");
    defer std.testing.allocator.free(root);

    var managed = try runtime_sqlite.openApplyProbeWithSleeper(std.testing.allocator, root, recordSleep);
    try exec(@ptrCast(managed.database.?.handle), "CREATE TABLE IF NOT EXISTS runtime_checkpoint_probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL);");
    try exec(@ptrCast(managed.database.?.handle), "INSERT INTO runtime_checkpoint_probe (value) VALUES ('bounded');");
    try managed.checkpointAndClose();
    try std.testing.expectEqual(runtime_sqlite.ComponentState.stopped, managed.status.state);
    try std.testing.expect(managed.database == null);
    managed.deinit();
}

test "RUNTIME-002 self-test is reachable while aggregate registration is out of owned scope" {
    try runtime_sqlite.selfTest();
}

fn absoluteTmpPath(tmp: *std.testing.TmpDir, sub_path: []const u8) ![]u8 {
    const real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(real);
    return try std.fs.path.join(std.testing.allocator, &.{ real, sub_path });
}

fn exec(db: *c.sqlite3, sql: [:0]const u8) !void {
    var error_message: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql.ptr, null, null, &error_message);
    defer if (error_message != null) c.sqlite3_free(error_message);
    if (rc == c.SQLITE_OK) return;
    return switch (rc) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.SqliteBusy,
        c.SQLITE_CANTOPEN, c.SQLITE_NOTADB, c.SQLITE_CORRUPT => error.SqliteUnavailable,
        else => error.SqliteUnavailable,
    };
}
