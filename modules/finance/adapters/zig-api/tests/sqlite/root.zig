const std = @import("std");
const app = @import("app");

pub fn selfTest() !void {
    try app.sqlite_adapter.selfTest();
}

test "SQLite adapter declarations remain reachable" {
    std.testing.refAllDecls(app.sqlite_adapter);
    try selfTest();
}
