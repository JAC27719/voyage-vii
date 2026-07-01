const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const component_id = "sqlite";
pub const open_timeout_ms: u32 = 5_000;
pub const busy_timeout_ms: c_int = 5_000;
pub const query_timeout_ms: u32 = 3_000;

pub const AdapterError = error{
    PathMustBeAbsolute,
    PathEscapesRoot,
    PathContainsParentTraversal,
    InvalidDatabasePath,
    OpenFailed,
    WalNotEnabled,
    ForeignKeysNotEnabled,
    BusyTimeoutMismatch,
    ProbeReturnedUnexpectedValue,
    SqliteBusy,
    SqliteUnavailable,
    MissingMigrationVersion,
    ChecksumDrift,
    DatabaseNewerThanExecutable,
    MigrationVersionGap,
    InvalidMigrationMetadata,
    InvalidDbml,
};

pub const ErrorCode = enum {
    sqlite_unavailable,
    sqlite_busy,
    sqlite_timeout,
    internal_error,
};

pub const Config = struct {
    data_root: []const u8,
    database_path: []const u8,
};

pub const Migration = struct {
    version: u32,
    name: []const u8,
    path: []const u8,
    sha256: []const u8,
};

pub const AppliedMigration = struct {
    version: u32,
    name: []const u8,
    sha256: []const u8,
};

pub const migrations = [_]Migration{
    .{
        .version = 1,
        .name = "schema_migrations",
        .path = "001_schema_migrations.sql",
        .sha256 = "a861b67186348f53d94e0c7862ff927f2eb4fee38f2fb788a9feee68b7bdcaa9",
    },
};

pub const Database = struct {
    handle: *c.sqlite3,

    pub fn open(allocator: std.mem.Allocator, config: Config) !Database {
        try validateDatabasePath(allocator, config.data_root, config.database_path);
        const path_z = try allocator.dupeZ(u8, config.database_path);
        defer allocator.free(path_z);

        var handle: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open_v2(
            path_z.ptr,
            &handle,
            c.SQLITE_OPEN_READWRITE | c.SQLITE_OPEN_CREATE | c.SQLITE_OPEN_FULLMUTEX,
            null,
        );
        if (rc != c.SQLITE_OK) {
            if (handle) |opened| _ = c.sqlite3_close(opened);
            return error.OpenFailed;
        }
        errdefer _ = c.sqlite3_close(handle.?);

        var database = Database{ .handle = handle.? };
        try database.configure();
        return database;
    }

    pub fn close(self: *Database) !void {
        const rc = c.sqlite3_close(self.handle);
        if (rc != c.SQLITE_OK) return mapSqliteRc(rc);
    }

    pub fn configure(self: Database) !void {
        try exec(self.handle, "PRAGMA foreign_keys=ON;");
        try exec(self.handle, "PRAGMA busy_timeout=5000;");
        try verifyJournalModeWal(self.handle);
        const foreign_keys = try queryInt(self.handle, "PRAGMA foreign_keys;");
        if (foreign_keys != 1) return error.ForeignKeysNotEnabled;
        const configured_busy_timeout = try queryInt(self.handle, "PRAGMA busy_timeout;");
        if (configured_busy_timeout != busy_timeout_ms) return error.BusyTimeoutMismatch;
    }

    pub fn healthProbe(self: Database) !void {
        const probe = try queryInt(self.handle, "SELECT 1;");
        if (probe != 1) return error.ProbeReturnedUnexpectedValue;
    }

    pub fn applyMigrations(self: Database, allocator: std.mem.Allocator) !void {
        try exec(self.handle, "BEGIN IMMEDIATE;");
        errdefer _ = c.sqlite3_exec(self.handle, "ROLLBACK;", null, null, null);

        const ledger_sql = try readMigrationSql(allocator, migrations[0]);
        defer allocator.free(ledger_sql);
        try execBytes(self.handle, ledger_sql);

        var applied = try loadAppliedMigrations(allocator, self.handle);
        defer applied.deinit(allocator);
        defer freeAppliedMigrations(allocator, applied.items);

        const pending = try planMigrations(applied.items, migrations[0..]);
        for (pending) |migration| {
            const sql = if (migration.version == 1) ledger_sql else try readMigrationSql(allocator, migration);
            defer if (migration.version != 1) allocator.free(sql);
            try execBytes(self.handle, sql);
            const insert_text = try std.fmt.allocPrint(
                allocator,
                "INSERT INTO schema_migrations (version, name, sha256) VALUES ({d}, '{s}', '{s}');",
                .{ migration.version, migration.name, migration.sha256 },
            );
            defer allocator.free(insert_text);
            const insert = try allocator.dupeZ(u8, insert_text);
            defer allocator.free(insert);
            try exec(self.handle, insert);
        }

        try exec(self.handle, "COMMIT;");
    }
};

pub fn validateDatabasePath(allocator: std.mem.Allocator, data_root: []const u8, database_path: []const u8) !void {
    if (!std.fs.path.isAbsolute(data_root) or !std.fs.path.isAbsolute(database_path)) {
        return error.PathMustBeAbsolute;
    }
    try rejectParentTraversal(data_root);
    try rejectParentTraversal(database_path);
    if (std.fs.path.dirname(database_path) == null) return error.InvalidDatabasePath;

    const root_real = try std.fs.cwd().realpathAlloc(allocator, data_root);
    defer allocator.free(root_real);
    const parent = std.fs.path.dirname(database_path).?;
    const parent_real = try std.fs.cwd().realpathAlloc(allocator, parent);
    defer allocator.free(parent_real);
    if (!isWithinRoot(root_real, parent_real)) return error.PathEscapesRoot;
}

fn rejectParentTraversal(path: []const u8) !void {
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |part| {
        if (std.mem.eql(u8, part, "..")) return error.PathContainsParentTraversal;
    }
}

fn isWithinRoot(root_real: []const u8, child_real: []const u8) bool {
    if (std.mem.eql(u8, root_real, child_real)) return true;
    if (!std.mem.startsWith(u8, child_real, root_real)) return false;
    const suffix = child_real[root_real.len..];
    return suffix.len > 0 and (suffix[0] == '/' or suffix[0] == '\\');
}

fn exec(db: *c.sqlite3, sql: [:0]const u8) !void {
    var error_message: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql.ptr, null, null, &error_message);
    defer if (error_message != null) c.sqlite3_free(error_message);
    if (rc != c.SQLITE_OK) return mapSqliteRc(rc);
}

fn execBytes(db: *c.sqlite3, sql: [:0]const u8) !void {
    var error_message: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql.ptr, null, null, &error_message);
    defer if (error_message != null) c.sqlite3_free(error_message);
    if (rc != c.SQLITE_OK) return mapSqliteRc(rc);
}

fn verifyJournalModeWal(db: *c.sqlite3) !void {
    var stmt: ?*c.sqlite3_stmt = null;
    try prepare(db, "PRAGMA journal_mode=WAL;", &stmt);
    defer _ = c.sqlite3_finalize(stmt);
    const rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_ROW) return mapSqliteRc(rc);
    const value = c.sqlite3_column_text(stmt, 0);
    if (value == null) return error.WalNotEnabled;
    if (!std.ascii.eqlIgnoreCase(std.mem.span(value), "wal")) return error.WalNotEnabled;
}

fn queryInt(db: *c.sqlite3, sql: [:0]const u8) !i64 {
    var stmt: ?*c.sqlite3_stmt = null;
    try prepare(db, sql, &stmt);
    defer _ = c.sqlite3_finalize(stmt);
    const rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_ROW) return mapSqliteRc(rc);
    return c.sqlite3_column_int64(stmt, 0);
}

fn prepare(db: *c.sqlite3, sql: [:0]const u8, stmt: *?*c.sqlite3_stmt) !void {
    const rc = c.sqlite3_prepare_v2(db, sql.ptr, -1, stmt, null);
    if (rc != c.SQLITE_OK) return mapSqliteRc(rc);
}

fn loadAppliedMigrations(allocator: std.mem.Allocator, db: *c.sqlite3) !std.ArrayList(AppliedMigration) {
    var stmt: ?*c.sqlite3_stmt = null;
    try prepare(db, "SELECT version, name, sha256 FROM schema_migrations ORDER BY version;", &stmt);
    defer _ = c.sqlite3_finalize(stmt);

    var applied = std.ArrayList(AppliedMigration){};
    errdefer {
        freeAppliedMigrations(allocator, applied.items);
        applied.deinit(allocator);
    }

    while (true) {
        const rc = c.sqlite3_step(stmt);
        if (rc == c.SQLITE_DONE) break;
        if (rc != c.SQLITE_ROW) return mapSqliteRc(rc);
        const version = c.sqlite3_column_int64(stmt, 0);
        if (version <= 0 or version > std.math.maxInt(u32)) return error.MigrationVersionGap;
        const name = c.sqlite3_column_text(stmt, 1) orelse return error.InvalidMigrationMetadata;
        const sha256 = c.sqlite3_column_text(stmt, 2) orelse return error.InvalidMigrationMetadata;
        try applied.append(allocator, .{
            .version = @intCast(version),
            .name = try allocator.dupe(u8, std.mem.span(name)),
            .sha256 = try allocator.dupe(u8, std.mem.span(sha256)),
        });
    }

    return applied;
}

fn freeAppliedMigrations(allocator: std.mem.Allocator, applied: []const AppliedMigration) void {
    for (applied) |entry| {
        allocator.free(entry.name);
        allocator.free(entry.sha256);
    }
}

pub fn planMigrations(applied: []const AppliedMigration, available: []const Migration) ![]const Migration {
    if (available.len == 0) return &.{};
    try validateAvailableMigrations(available);
    for (applied) |entry| {
        if (entry.version > available[available.len - 1].version) return error.DatabaseNewerThanExecutable;
    }

    var last_applied: u32 = 0;
    for (applied) |entry| {
        if (entry.version != last_applied + 1) return error.MigrationVersionGap;
        try validateAppliedMigration(entry, available[@intCast(entry.version - 1)]);
        last_applied = entry.version;
    }
    return available[@intCast(last_applied)..];
}

fn validateAvailableMigrations(available: []const Migration) !void {
    for (available, 0..) |migration, index| {
        if (migration.version != index + 1) return error.MigrationVersionGap;
        if (migration.name.len == 0 or migration.path.len == 0) return error.InvalidMigrationMetadata;
        try validateSha256(migration.sha256);
        try verifyMigrationChecksum(std.heap.page_allocator, migration);
    }
}

fn validateAppliedMigration(applied: AppliedMigration, expected: Migration) !void {
    if (applied.version != expected.version) return error.MissingMigrationVersion;
    if (!std.mem.eql(u8, applied.name, expected.name)) return error.ChecksumDrift;
    if (!std.mem.eql(u8, applied.sha256, expected.sha256)) return error.ChecksumDrift;
}

pub fn verifyMigrationChecksum(allocator: std.mem.Allocator, migration: Migration) !void {
    const sql = try readMigrationSql(allocator, migration);
    defer allocator.free(sql);
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(sql, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    if (!std.mem.eql(u8, &hex, migration.sha256)) return error.ChecksumDrift;
}

fn readMigrationSql(allocator: std.mem.Allocator, migration: Migration) ![:0]u8 {
    const prefixes = [_][]const u8{
        "services/api/migrations",
        "migrations",
    };
    for (prefixes) |prefix| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, migration.path });
        defer allocator.free(path);
        const bytes = std.fs.cwd().readFileAllocOptions(
            allocator,
            path,
            64 * 1024,
            null,
            .of(u8),
            0,
        ) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        return bytes;
    }
    return error.FileNotFound;
}

fn validateSha256(hash: []const u8) !void {
    if (hash.len != 64) return error.InvalidMigrationMetadata;
    for (hash) |byte| {
        if (!((byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))) {
            return error.InvalidMigrationMetadata;
        }
    }
}

fn mapSqliteRc(rc: c_int) AdapterError {
    return switch (rc) {
        c.SQLITE_BUSY, c.SQLITE_LOCKED => error.SqliteBusy,
        c.SQLITE_CANTOPEN, c.SQLITE_NOTADB, c.SQLITE_CORRUPT => error.SqliteUnavailable,
        else => error.SqliteUnavailable,
    };
}

pub fn mapNativeError(err: anyerror) ErrorCode {
    return switch (err) {
        error.SqliteBusy => .sqlite_busy,
        error.Timeout, error.WouldBlock => .sqlite_timeout,
        error.OpenFailed, error.SqliteUnavailable => .sqlite_unavailable,
        else => .internal_error,
    };
}

pub const SanitizedDiagnostic = struct {
    operation: []const u8,
    elapsed_ms: u64,
};

pub fn sanitizedDiagnostic(operation: []const u8, elapsed_ms: u64) SanitizedDiagnostic {
    return .{ .operation = operation, .elapsed_ms = elapsed_ms };
}

pub fn containsSecretLikeText(message: []const u8) bool {
    const needles = [_][]const u8{
        "password",
        "secret",
        "credential",
        "sqlite-path",
        ".sqlite",
        "select ",
        "insert ",
        "update ",
        "delete ",
        "authorization",
    };
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(message, needle) != null) return true;
    }
    return false;
}

pub fn selfTest() !void {
    try verifyMigrationChecksum(std.heap.page_allocator, migrations[0]);
    _ = try planMigrations(&.{}, &migrations);
    if (open_timeout_ms != 5_000) return error.InvalidMigrationMetadata;
    if (busy_timeout_ms != 5_000) return error.InvalidMigrationMetadata;
    if (query_timeout_ms != 3_000) return error.InvalidMigrationMetadata;
    try expectMigrationAndDbmlStaySynchronized(std.heap.page_allocator);
}

test "API-005 migration planning handles fresh retained drift gap and newer database" {
    const available = migrations[0..];
    const fresh = try planMigrations(&.{}, available);
    try std.testing.expectEqual(@as(usize, 1), fresh.len);
    try std.testing.expectEqual(@as(u32, 1), fresh[0].version);

    const retained = try planMigrations(&.{
        .{ .version = 1, .name = "schema_migrations", .sha256 = available[0].sha256 },
    }, available);
    try std.testing.expectEqual(@as(usize, 0), retained.len);

    try std.testing.expectError(error.ChecksumDrift, planMigrations(&.{
        .{ .version = 1, .name = "schema_migrations", .sha256 = "0000000000000000000000000000000000000000000000000000000000000000" },
    }, available));
    try std.testing.expectError(error.MigrationVersionGap, planMigrations(&.{
        .{ .version = 2, .name = "future", .sha256 = available[0].sha256 },
        .{ .version = 3, .name = "further_future", .sha256 = available[0].sha256 },
    }, available));
    try std.testing.expectError(error.DatabaseNewerThanExecutable, planMigrations(&.{
        .{ .version = 2, .name = "future", .sha256 = available[0].sha256 },
    }, available));
}

test "API-005 opens applies probes and retains SQLite database" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root/sqlite");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "root" });
    defer std.testing.allocator.free(root);
    const db_path = try std.fs.path.join(std.testing.allocator, &.{ root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(db_path);

    var database = try Database.open(std.testing.allocator, .{ .data_root = root, .database_path = db_path });
    try database.applyMigrations(std.testing.allocator);
    try database.healthProbe();
    try database.close();

    var retained = try Database.open(std.testing.allocator, .{ .data_root = root, .database_path = db_path });
    try retained.applyMigrations(std.testing.allocator);
    try std.testing.expectEqual(@as(i64, 1), try queryInt(retained.handle, "SELECT COUNT(*) FROM schema_migrations;"));
    try retained.close();
}

test "API-005 rejects invalid roots checksum drift and newer database" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root/sqlite");
    try tmp.dir.makePath("outside");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "root" });
    defer std.testing.allocator.free(root);
    const outside = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "outside", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(outside);
    try std.testing.expectError(error.PathEscapesRoot, validateDatabasePath(std.testing.allocator, root, outside));

    const db_path = try std.fs.path.join(std.testing.allocator, &.{ root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(db_path);
    var database = try Database.open(std.testing.allocator, .{ .data_root = root, .database_path = db_path });
    try database.applyMigrations(std.testing.allocator);
    try exec(database.handle, "UPDATE schema_migrations SET sha256 = '0000000000000000000000000000000000000000000000000000000000000000' WHERE version = 1;");
    try std.testing.expectError(error.ChecksumDrift, database.applyMigrations(std.testing.allocator));
    try exec(database.handle, "DELETE FROM schema_migrations;");
    try database.applyMigrations(std.testing.allocator);
    try exec(database.handle, "INSERT INTO schema_migrations (version, name, sha256) VALUES (2, 'future', '0000000000000000000000000000000000000000000000000000000000000000');");
    try std.testing.expectError(error.DatabaseNewerThanExecutable, database.applyMigrations(std.testing.allocator));
    try database.close();
}

test "API-005 exposes busy and sanitized diagnostic behavior" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("root/sqlite");
    const tmp_real = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_real);
    const root = try std.fs.path.join(std.testing.allocator, &.{ tmp_real, "root" });
    defer std.testing.allocator.free(root);
    const db_path = try std.fs.path.join(std.testing.allocator, &.{ root, "sqlite", "voyage-vii.sqlite3" });
    defer std.testing.allocator.free(db_path);

    var first = try Database.open(std.testing.allocator, .{ .data_root = root, .database_path = db_path });
    defer first.close() catch {};
    var second = try Database.open(std.testing.allocator, .{ .data_root = root, .database_path = db_path });
    defer second.close() catch {};
    try exec(first.handle, "BEGIN IMMEDIATE;");
    defer exec(first.handle, "ROLLBACK;") catch {};
    try std.testing.expectError(error.SqliteBusy, exec(second.handle, "BEGIN IMMEDIATE;"));

    const diagnostic = sanitizedDiagnostic("sqlite_probe", 42);
    try std.testing.expectEqualStrings("sqlite_probe", diagnostic.operation);
    try std.testing.expect(!containsSecretLikeText(diagnostic.operation));
    try std.testing.expect(containsSecretLikeText("sqlite-path=C:\\data\\voyage.sqlite3"));
    try std.testing.expect(containsSecretLikeText("SELECT 1"));
}

test "API-005 migration SQL and DBML stay synchronized" {
    try expectMigrationAndDbmlStaySynchronized(std.testing.allocator);
}

fn expectMigrationAndDbmlStaySynchronized(allocator: std.mem.Allocator) !void {
    const sql = try readMigrationSql(allocator, migrations[0]);
    defer allocator.free(sql);
    const dbml = try readDbml(allocator);
    defer allocator.free(dbml);

    const required_sql = [_][]const u8{
        "CREATE TABLE IF NOT EXISTS schema_migrations",
        "version INTEGER NOT NULL PRIMARY KEY",
        "name TEXT NOT NULL UNIQUE",
        "sha256 TEXT NOT NULL CHECK",
        "applied_at TEXT NOT NULL DEFAULT (strftime",
        "CREATE UNIQUE INDEX IF NOT EXISTS schema_migrations_name_key",
    };
    for (required_sql) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, sql, needle) != null);
    }

    const parsed = try parseImplementedDbml(dbml);
    try std.testing.expect(parsed.schema_migrations);
    try std.testing.expect(parsed.version_pk_not_null);
    try std.testing.expect(parsed.name_unique_not_null);
    try std.testing.expect(parsed.sha256_text_not_null);
    try std.testing.expect(parsed.sha256_check_constraint);
    try std.testing.expect(parsed.applied_at_text_default);
    try std.testing.expect(parsed.name_unique_index);
    try std.testing.expect(!parsed.has_relations);
    try std.testing.expect(!parsed.has_triggers);
}

const ImplementedDbml = struct {
    schema_migrations: bool = false,
    version_pk_not_null: bool = false,
    name_unique_not_null: bool = false,
    sha256_text_not_null: bool = false,
    sha256_check_constraint: bool = false,
    applied_at_text_default: bool = false,
    name_unique_index: bool = false,
    has_relations: bool = false,
    has_triggers: bool = false,
};

fn parseImplementedDbml(dbml: []const u8) !ImplementedDbml {
    var parsed = ImplementedDbml{};
    var in_schema_migrations = false;
    var table_depth: u8 = 0;
    var in_indexes = false;

    var lines = std.mem.splitScalar(u8, dbml, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "Ref:")) parsed.has_relations = true;
        if (std.mem.startsWith(u8, line, "Trigger ")) parsed.has_triggers = true;

        if (!in_schema_migrations) {
            if (std.mem.eql(u8, line, "Table schema_migrations {")) {
                parsed.schema_migrations = true;
                in_schema_migrations = true;
                table_depth = 1;
            }
            continue;
        }

        if (std.mem.eql(u8, line, "indexes {")) {
            in_indexes = true;
            table_depth += 1;
            continue;
        }
        if (std.mem.eql(u8, line, "}")) {
            if (table_depth == 0) return error.InvalidDbml;
            table_depth -= 1;
            if (in_indexes and table_depth == 1) in_indexes = false;
            if (table_depth == 0) in_schema_migrations = false;
            continue;
        }

        if (in_indexes) {
            if (std.mem.eql(u8, line, "name [unique, name: \"schema_migrations_name_key\"]")) {
                parsed.name_unique_index = true;
            }
            continue;
        }

        if (std.mem.startsWith(u8, line, "version integer ")) {
            parsed.version_pk_not_null = hasAll(line, &.{ "[", "pk", "not null", "]" });
        } else if (std.mem.startsWith(u8, line, "name text ")) {
            parsed.name_unique_not_null = hasAll(line, &.{ "[", "unique", "not null", "]" });
        } else if (std.mem.startsWith(u8, line, "sha256 text ")) {
            parsed.sha256_text_not_null = hasAll(line, &.{ "[", "not null", "]" });
            parsed.sha256_check_constraint = hasAll(line, &.{ "CHECK", "length(sha256) = 64", "sha256 NOT GLOB" });
        } else if (std.mem.startsWith(u8, line, "applied_at text ")) {
            parsed.applied_at_text_default = hasAll(line, &.{ "[", "not null", "strftime", "]" });
        }
    }

    if (table_depth != 0) return error.InvalidDbml;
    return parsed;
}

fn hasAll(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, haystack, needle) == null) return false;
    }
    return true;
}

fn readDbml(allocator: std.mem.Allocator) ![]u8 {
    const candidates = [_][]const u8{
        "docs/database/sqlite.dbml",
        "../../docs/database/sqlite.dbml",
    };
    for (candidates) |path| {
        return std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
    }
    return error.FileNotFound;
}
