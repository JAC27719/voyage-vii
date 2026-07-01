const std = @import("std");
const builtin = @import("builtin");

const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

const busy_timeout_ms = 5000;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("usage: {s} <database-path>\n", .{args[0]});
        return error.InvalidArguments;
    }

    const db_path = try allocator.dupeZ(u8, args[1]);
    defer allocator.free(db_path);

    std.debug.print(
        "native_target={s}-{s} pointer_bits={d}\n",
        .{ @tagName(builtin.cpu.arch), @tagName(builtin.os.tag), @bitSizeOf(usize) },
    );
    std.debug.print("sqlite_header_version={s}\n", .{sqlite.SQLITE_VERSION});
    std.debug.print("sqlite_header_source_id={s}\n", .{sqlite.SQLITE_SOURCE_ID});

    var db: ?*sqlite.sqlite3 = null;
    try checkOpen(sqlite.sqlite3_open_v2(
        db_path.ptr,
        &db,
        sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_FULLMUTEX,
        null,
    ));
    defer {
        if (db) |handle| {
            const rc = sqlite.sqlite3_close(handle);
            if (rc == sqlite.SQLITE_OK) {
                std.debug.print("close=ok\n", .{});
            } else {
                std.debug.print("close=failed rc={d}\n", .{rc});
            }
        }
    }

    const handle = db orelse return error.DatabaseOpenMissingHandle;
    try exec(handle, "PRAGMA foreign_keys=ON;");
    try exec(handle, "PRAGMA busy_timeout=5000;");

    try verifyJournalModeWal(handle);

    const foreign_keys = try queryInt(handle, "PRAGMA foreign_keys;");
    if (foreign_keys != 1) return error.ForeignKeysNotEnabled;
    std.debug.print("foreign_keys=ok value={d}\n", .{foreign_keys});

    const busy_timeout = try queryInt(handle, "PRAGMA busy_timeout;");
    if (busy_timeout != busy_timeout_ms) return error.BusyTimeoutMismatch;
    std.debug.print("busy_timeout=ok value_ms={d}\n", .{busy_timeout});

    try exec(handle, "BEGIN IMMEDIATE;");
    errdefer _ = sqlite.sqlite3_exec(handle, "ROLLBACK;", null, null, null);
    try exec(
        handle,
        \\CREATE TABLE IF NOT EXISTS schema_migrations (
        \\  version INTEGER NOT NULL PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  sha256 TEXT NOT NULL CHECK (length(sha256) = 64),
        \\  applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
        \\  UNIQUE(name)
        \\);
    );
    try exec(
        handle,
        \\INSERT OR IGNORE INTO schema_migrations(version, name, sha256)
        \\VALUES (1, 'feas_004_schema_migrations', '0000000000000000000000000000000000000000000000000000000000000000');
    );
    try exec(handle, "COMMIT;");
    std.debug.print("transaction=ok migration_table=ok\n", .{});

    const probe = try queryInt(handle, "SELECT 1;");
    if (probe != 1) return error.SelectProbeFailed;
    std.debug.print("select_probe=ok value={d}\n", .{probe});

    const migration_count = try queryInt(handle, "SELECT COUNT(*) FROM schema_migrations;");
    if (migration_count != 1) return error.MigrationCountMismatch;
    std.debug.print("migration_count=ok value={d}\n", .{migration_count});
}

fn checkOpen(rc: c_int) !void {
    if (rc != sqlite.SQLITE_OK) {
        std.debug.print("open=failed rc={d}\n", .{rc});
        return error.SqliteOpenFailed;
    }
    std.debug.print("open=ok\n", .{});
}

fn exec(db: *sqlite.sqlite3, sql: [:0]const u8) !void {
    var error_message: [*c]u8 = null;
    const rc = sqlite.sqlite3_exec(db, sql.ptr, null, null, &error_message);
    defer {
        if (error_message != null) sqlite.sqlite3_free(error_message);
    }
    if (rc != sqlite.SQLITE_OK) {
        std.debug.print("exec=failed rc={d} sql={s}\n", .{ rc, sql });
        return error.SqliteExecFailed;
    }
}

fn queryInt(db: *sqlite.sqlite3, sql: [:0]const u8) !i64 {
    var stmt: ?*sqlite.sqlite3_stmt = null;
    try prepare(db, sql, &stmt);
    defer _ = sqlite.sqlite3_finalize(stmt);

    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_ROW) return error.SqliteExpectedRow;
    return sqlite.sqlite3_column_int64(stmt, 0);
}

fn verifyJournalModeWal(db: *sqlite.sqlite3) !void {
    var stmt: ?*sqlite.sqlite3_stmt = null;
    try prepare(db, "PRAGMA journal_mode=WAL;", &stmt);
    defer _ = sqlite.sqlite3_finalize(stmt);

    const rc = sqlite.sqlite3_step(stmt);
    if (rc != sqlite.SQLITE_ROW) return error.SqliteExpectedRow;
    const value = sqlite.sqlite3_column_text(stmt, 0);
    if (value == null) return error.SqliteNullText;
    const journal_mode = std.mem.span(value);
    if (!std.ascii.eqlIgnoreCase(journal_mode, "wal")) return error.WalNotEnabled;
    std.debug.print("wal=ok journal_mode={s}\n", .{journal_mode});
}

fn prepare(db: *sqlite.sqlite3, sql: [:0]const u8, stmt: *?*sqlite.sqlite3_stmt) !void {
    const rc = sqlite.sqlite3_prepare_v2(db, sql.ptr, -1, stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        std.debug.print("prepare=failed rc={d} sql={s}\n", .{ rc, sql });
        return error.SqlitePrepareFailed;
    }
}
