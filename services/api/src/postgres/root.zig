const std = @import("std");
const pg = @import("pg");

pub const component_id = "postgresql";
pub const max_pool_size: u8 = 2;
pub const connect_timeout_ms: u32 = 5_000;
pub const acquisition_timeout_ms: u32 = 5_000;
pub const query_timeout_ms: u32 = 3_000;
pub const advisory_lock_key: i64 = 0x766f7961676537;

pub const MigrationError = error{
    MissingMigrationVersion,
    ChecksumDrift,
    DatabaseNewerThanExecutable,
    MigrationVersionGap,
    InvalidMigrationMetadata,
    ProbeReturnedUnexpectedValue,
};

pub const ErrorCode = enum {
    postgres_unavailable,
    postgres_authentication_failed,
    postgres_timeout,
    internal_error,
};

pub const Config = struct {
    host: []const u8,
    port: u16,
    database: []const u8,
    username: []const u8,
    password: ?[]const u8,
    application_name: []const u8 = "voyage-vii-api",
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
        .sha256 = "6d3048bb3f1d83683f55c995b92cb8ecc2b179d2c9611255b9a5d47b6a2b98e8",
    },
};

pub fn initPool(allocator: std.mem.Allocator, config: Config) !*pg.Pool {
    return try pg.Pool.init(allocator, .{
        .size = max_pool_size,
        .timeout = acquisition_timeout_ms,
        .connect = .{
            .host = config.host,
            .port = config.port,
            .tls = .off,
        },
        .auth = .{
            .username = config.username,
            .password = config.password,
            .database = config.database,
            .timeout = connect_timeout_ms,
            .application_name = config.application_name,
        },
    });
}

pub fn openConnection(allocator: std.mem.Allocator, config: Config) !pg.Conn {
    return pg.Conn.openAndAuth(allocator, .{
        .host = config.host,
        .port = config.port,
        .tls = .off,
    }, .{
        .username = config.username,
        .password = config.password,
        .database = config.database,
        .timeout = connect_timeout_ms,
        .application_name = config.application_name,
    });
}

pub fn healthProbe(pool: *pg.Pool) !void {
    var row = (try pool.rowOpts("SELECT 1", .{}, .{
        .timeout = query_timeout_ms,
    })) orelse return error.ProbeReturnedUnexpectedValue;
    defer row.deinit() catch {};
    if (try row.get(i32, 0) != 1) return error.ProbeReturnedUnexpectedValue;
}

pub fn applyMigrations(pool: *pg.Pool) !void {
    var conn = try pool.acquire();
    defer pool.release(conn);
    try conn.begin();
    errdefer conn.rollback() catch {};
    _ = try conn.execOpts("SELECT pg_advisory_xact_lock($1)", .{advisory_lock_key}, .{ .timeout = query_timeout_ms });

    const allocator = std.heap.page_allocator;
    const ledger_sql = try readMigrationSql(allocator, migrations[0]);
    defer allocator.free(ledger_sql);
    _ = try conn.execOpts(ledger_sql, .{}, .{ .timeout = query_timeout_ms });

    var applied = try loadAppliedMigrations(allocator, conn);
    defer freeAppliedMigrations(allocator, applied.items);
    defer applied.deinit(allocator);

    const pending = try planMigrations(applied.items, migrations[0..]);
    for (pending) |migration| {
        const sql = if (migration.version == 1) ledger_sql else try readMigrationSql(allocator, migration);
        defer if (migration.version != 1) allocator.free(sql);
        _ = try conn.execOpts(sql, .{}, .{ .timeout = query_timeout_ms });
        _ = try conn.execOpts(
            "INSERT INTO schema_migrations (version, name, sha256) VALUES ($1, $2, $3)",
            .{ migration.version, migration.name, migration.sha256 },
            .{ .timeout = query_timeout_ms },
        );
    }

    try conn.commit();
}

fn loadAppliedMigrations(allocator: std.mem.Allocator, conn: *pg.Conn) !std.ArrayList(AppliedMigration) {
    var result = try conn.queryOpts(
        "SELECT version, name, sha256 FROM schema_migrations ORDER BY version",
        .{},
        .{ .timeout = query_timeout_ms },
    );
    defer result.deinit();

    var applied = std.ArrayList(AppliedMigration){};
    errdefer {
        freeAppliedMigrations(allocator, applied.items);
        applied.deinit(allocator);
    }

    while (try result.next()) |row| {
        const db_version = try row.get(i32, 0);
        if (db_version <= 0) return error.MigrationVersionGap;
        const name = try row.get([]const u8, 1);
        const sha256 = try row.get([]const u8, 2);
        try applied.append(allocator, .{
            .version = @intCast(db_version),
            .name = try allocator.dupe(u8, name),
            .sha256 = try allocator.dupe(u8, sha256),
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

fn readMigrationSql(allocator: std.mem.Allocator, migration: Migration) ![]u8 {
    const prefixes = [_][]const u8{
        "services/api/migrations",
        "migrations",
    };
    for (prefixes) |prefix| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, migration.path });
        defer allocator.free(path);
        return std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
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

pub fn mapNativeError(err: anyerror) ErrorCode {
    return switch (err) {
        error.PG => .postgres_authentication_failed,
        error.Timeout, error.WouldBlock, error.PoolExhausted => .postgres_timeout,
        error.ConnectionRefused, error.NetworkUnreachable, error.ConnectionTimedOut, error.HostLacksNetworkAddresses => .postgres_unavailable,
        else => .internal_error,
    };
}

pub fn sanitizedDiagnostic(operation: []const u8, elapsed_ms: u64) SanitizedDiagnostic {
    return .{ .operation = operation, .elapsed_ms = elapsed_ms };
}

pub const SanitizedDiagnostic = struct {
    operation: []const u8,
    elapsed_ms: u64,
};

pub fn containsSecretLikeText(message: []const u8) bool {
    const needles = [_][]const u8{
        "password",
        "secret",
        "credential",
        "postgres-password-file",
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
    for (migrations) |migration| try verifyMigrationChecksum(std.heap.page_allocator, migration);
    _ = try planMigrations(&.{}, &migrations);
    if (max_pool_size != 2) return error.InvalidPostgresConfiguration;
    if (connect_timeout_ms != 5_000) return error.InvalidPostgresConfiguration;
    if (acquisition_timeout_ms != 5_000) return error.InvalidPostgresConfiguration;
    if (query_timeout_ms != 3_000) return error.InvalidPostgresConfiguration;
}

test "API-002 migration planning handles fresh retained drift gap and newer database" {
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

test "API-002 pool constants and native errors stay portable" {
    try std.testing.expectEqual(@as(u8, 2), max_pool_size);
    try std.testing.expectEqual(@as(u32, 5_000), acquisition_timeout_ms);
    try std.testing.expectEqual(ErrorCode.postgres_timeout, mapNativeError(error.PoolExhausted));
}

test "API-002 migration SQL and DBML stay synchronized" {
    try expectMigrationAndDbmlStaySynchronized();
}

test "API-002 diagnostics do not contain credentials or SQL values" {
    try expectNoSecretDiagnostics();
}

fn expectMigrationAndDbmlStaySynchronized() !void {
    const sql = try readMigrationSql(std.testing.allocator, migrations[0]);
    defer std.testing.allocator.free(sql);
    const dbml = try readDbml(std.testing.allocator);
    defer std.testing.allocator.free(dbml);

    const required_sql = [_][]const u8{
        "CREATE TABLE IF NOT EXISTS schema_migrations",
        "version integer PRIMARY KEY",
        "name text NOT NULL UNIQUE",
        "sha256 char(64) NOT NULL CHECK",
        "applied_at timestamptz NOT NULL DEFAULT now()",
    };
    for (required_sql) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, sql, needle) != null);
    }

    const parsed = try parseImplementedDbml(dbml);
    try std.testing.expect(parsed.schema_migrations);
    try std.testing.expect(parsed.version_pk_not_null);
    try std.testing.expect(parsed.name_unique_not_null);
    try std.testing.expect(parsed.sha256_char64_not_null);
    try std.testing.expect(parsed.sha256_check_constraint);
    try std.testing.expect(parsed.applied_at_timestamp_default);
    try std.testing.expect(parsed.name_unique_index);
    try std.testing.expect(!parsed.has_relations);
}

const ImplementedDbml = struct {
    schema_migrations: bool = false,
    version_pk_not_null: bool = false,
    name_unique_not_null: bool = false,
    sha256_char64_not_null: bool = false,
    sha256_check_constraint: bool = false,
    applied_at_timestamp_default: bool = false,
    name_unique_index: bool = false,
    has_relations: bool = false,
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
        } else if (std.mem.startsWith(u8, line, "sha256 char(64) ")) {
            parsed.sha256_char64_not_null = hasAll(line, &.{ "[", "not null", "]" });
            parsed.sha256_check_constraint = hasAll(line, &.{ "CHECK", "sha256 ~", "^[0-9a-f]{64}$" });
        } else if (std.mem.startsWith(u8, line, "applied_at timestamptz ")) {
            parsed.applied_at_timestamp_default = hasAll(line, &.{ "[", "not null", "default: `now()`", "]" });
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
        "docs/database/postgresql.dbml",
        "../../docs/database/postgresql.dbml",
    };
    for (candidates) |path| {
        return std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
    }
    return error.FileNotFound;
}

fn expectNoSecretDiagnostics() !void {
    const diagnostic = sanitizedDiagnostic("postgres_connect", 42);
    try std.testing.expectEqualStrings("postgres_connect", diagnostic.operation);
    try std.testing.expect(!containsSecretLikeText(diagnostic.operation));
    try std.testing.expect(!containsSecretLikeText("postgres_probe elapsed_ms=42"));
    try std.testing.expect(containsSecretLikeText("password=value"));
    try std.testing.expect(containsSecretLikeText("SELECT 1"));
}

const live_enabled_var = "VOYAGE_API_POSTGRES_LIVE";
const nonresponsive_host_var = "VOYAGE_API_POSTGRES_NONRESPONSIVE_HOST";

const LiveConfig = struct {
    env: std.process.EnvMap,
    config: Config,

    fn deinit(self: *LiveConfig) void {
        self.env.deinit();
    }
};

fn loadLiveConfig(allocator: std.mem.Allocator) !LiveConfig {
    if (!try std.process.hasEnvVar(allocator, live_enabled_var)) return error.SkipZigTest;
    var env = try std.process.getEnvMap(allocator);
    errdefer env.deinit();

    const host = env.get("PGHOST") orelse "127.0.0.1";
    const port_text = env.get("PGPORT") orelse "5432";
    const database = env.get("PGDATABASE") orelse "postgres";
    const username = env.get("PGUSER") orelse "postgres";
    const password = env.get("PGPASSWORD");
    const port = try std.fmt.parseInt(u16, port_text, 10);

    return .{
        .env = env,
        .config = .{
            .host = host,
            .port = port,
            .database = database,
            .username = username,
            .password = password,
        },
    };
}

fn resetSchemaMigrations(config: Config) !void {
    var conn = try openConnection(std.testing.allocator, config);
    defer conn.deinit();
    _ = try conn.execOpts(
        "DROP TABLE IF EXISTS schema_migrations",
        .{},
        .{ .timeout = query_timeout_ms },
    );
}

fn openLivePool(config: Config) !*pg.Pool {
    return initPool(std.testing.allocator, config);
}

fn scalarI64(pool: *pg.Pool, sql: []const u8) !i64 {
    var row = (try pool.rowOpts(sql, .{}, .{ .timeout = query_timeout_ms })) orelse return error.MissingRow;
    defer row.deinit() catch {};
    return try row.get(i64, 0);
}

test "API-002 live migrations handle fresh and retained databases" {
    var live = try loadLiveConfig(std.testing.allocator);
    defer live.deinit();
    try resetSchemaMigrations(live.config);

    var pool = try openLivePool(live.config);
    defer pool.deinit();

    try applyMigrations(pool);
    try std.testing.expectEqual(@as(i64, 1), try scalarI64(pool, "SELECT count(*) FROM schema_migrations"));

    try applyMigrations(pool);
    try std.testing.expectEqual(@as(i64, 1), try scalarI64(pool, "SELECT count(*) FROM schema_migrations"));
}

test "API-002 live migrations serialize concurrent applicators" {
    var live = try loadLiveConfig(std.testing.allocator);
    defer live.deinit();
    try resetSchemaMigrations(live.config);

    var pool = try openLivePool(live.config);
    defer pool.deinit();

    var first = MigrationThread{ .pool = pool };
    var second = MigrationThread{ .pool = pool };
    const first_thread = try std.Thread.spawn(.{}, MigrationThread.run, .{&first});
    const second_thread = try std.Thread.spawn(.{}, MigrationThread.run, .{&second});
    first_thread.join();
    second_thread.join();

    if (first.err) |err| return err;
    if (second.err) |err| return err;
    try std.testing.expectEqual(@as(i64, 1), try scalarI64(pool, "SELECT count(*) FROM schema_migrations"));
}

const MigrationThread = struct {
    pool: *pg.Pool,
    err: ?anyerror = null,

    fn run(self: *MigrationThread) void {
        applyMigrations(self.pool) catch |err| {
            self.err = err;
        };
    }
};

test "API-002 live migrations reject checksum drift and newer schema" {
    var live = try loadLiveConfig(std.testing.allocator);
    defer live.deinit();
    try resetSchemaMigrations(live.config);

    var pool = try openLivePool(live.config);
    defer pool.deinit();
    try applyMigrations(pool);

    _ = try pool.execOpts(
        "UPDATE schema_migrations SET sha256 = $1 WHERE version = 1",
        .{"0000000000000000000000000000000000000000000000000000000000000000"},
        .{ .timeout = query_timeout_ms },
    );
    try std.testing.expectError(error.ChecksumDrift, applyMigrations(pool));

    try resetSchemaMigrations(live.config);
    try applyMigrations(pool);
    _ = try pool.execOpts(
        "INSERT INTO schema_migrations (version, name, sha256) VALUES ($1, $2, $3)",
        .{ @as(i32, 2), "future", migrations[0].sha256 },
        .{ .timeout = query_timeout_ms },
    );
    try std.testing.expectError(error.DatabaseNewerThanExecutable, applyMigrations(pool));
}

test "API-002 live pool exhaustion is bounded by acquisition timeout" {
    var live = try loadLiveConfig(std.testing.allocator);
    defer live.deinit();

    var pool = try openLivePool(live.config);
    defer pool.deinit();

    const first = try pool.acquire();
    defer pool.release(first);
    const second = try pool.acquire();
    defer pool.release(second);

    const started = std.time.milliTimestamp();
    try std.testing.expectError(error.Timeout, pool.acquire());
    const elapsed = std.time.milliTimestamp() - started;
    try std.testing.expect(elapsed >= acquisition_timeout_ms);
    try std.testing.expect(elapsed < acquisition_timeout_ms + 2_000);
}

test "API-002 unavailable loopback server fails without leaking a pool" {
    const port = try closedLoopbackPort();
    try std.testing.expectError(error.ConnectionRefused, initPool(std.testing.allocator, .{
        .host = "127.0.0.1",
        .port = port,
        .database = "postgres",
        .username = "postgres",
        .password = null,
    }));
}

test "API-002 nonresponsive destination observes frozen connect deadline" {
    const host = std.process.getEnvVarOwned(std.testing.allocator, nonresponsive_host_var) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return error.SkipZigTest,
        else => return err,
    };
    defer std.testing.allocator.free(host);

    const started = std.time.milliTimestamp();
    const result = initPool(std.testing.allocator, .{
        .host = host,
        .port = 5432,
        .database = "postgres",
        .username = "postgres",
        .password = null,
    });
    try std.testing.expectError(error.ConnectionTimedOut, result);
    const elapsed = std.time.milliTimestamp() - started;
    try std.testing.expect(elapsed >= connect_timeout_ms);
    try std.testing.expect(elapsed < connect_timeout_ms + 2_000);
}

fn closedLoopbackPort() !u16 {
    const address = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try address.listen(.{ .reuse_address = true });
    const port = server.listen_address.getPort();
    server.deinit();
    return port;
}
