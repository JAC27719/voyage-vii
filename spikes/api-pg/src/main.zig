const std = @import("std");
const api = @import("api");
const pg = @import("pg");

const connect_timeout_ms = 5_000;
const query_timeout_ms = 3_000;

pub fn main() void {
    run() catch |err| {
        std.debug.print("spike_exit=failed error={s}\n", .{@errorName(err)});
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
    if (std.mem.eql(u8, args[1], "pg-probe")) return postgresProbe(allocator, args[2..]);
    return usage();
}

fn usage() error{InvalidArguments} {
    std.debug.print(
        \\usage:
        \\  api-pg-spike serve [port]
        \\  api-pg-spike pg-probe <host> <port> <database> <username>
        \\
        \\pg-probe reads the password from PGPASSWORD and never prints it.
        \\
    , .{});
    return error.InvalidArguments;
}

fn deterministicEndpoint(_: *api.Context) api.Response {
    return api.Response.jsonRaw("{\"dependency\":\"api.zig\",\"status\":\"ok\"}");
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

fn serve(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len > 1) return usage();
    const port = if (args.len == 1)
        try std.fmt.parseInt(u16, args[0], 10)
    else
        18_080;

    var app = try api.App.init(allocator, .{
        .title = "FEAS-001",
        .version = "0.0.0",
        .health_url = null,
    });
    defer app.deinit();

    try app.get("/probe", deterministicEndpoint);
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

fn postgresProbe(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !void {
    if (args.len != 4) return usage();

    const port = try std.fmt.parseInt(u16, args[1], 10);
    const password = std.process.getEnvVarOwned(allocator, "PGPASSWORD") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (password) |value| {
        @memset(value, 0);
        allocator.free(value);
    };

    var conn = pg.Conn.openAndAuth(allocator, .{
        .host = args[0],
        .port = port,
        .tls = .off,
    }, .{
        .username = args[3],
        .password = password,
        .database = args[2],
        .timeout = connect_timeout_ms,
        .application_name = "voyage-vii-feas-001",
    }) catch |err| {
        const category: []const u8 = if (err == error.PG)
            "authentication_failed"
        else
            "server_unavailable";
        std.debug.print("pg_probe=failed category={s} error={s}\n", .{
            category,
            @errorName(err),
        });
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
}
