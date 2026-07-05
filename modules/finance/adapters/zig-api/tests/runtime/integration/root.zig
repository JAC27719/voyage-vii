const std = @import("std");
const main = @import("app");

pub fn selfTest() !void {
    try main.runSelfTest();

    const command = try main.parseCommand(&.{
        "serve",
        "--runtime",
        "managed",
        "--runtime-root",
        "C:\\runtime",
        "--data-root",
        "C:\\data",
        "--allowed-origin",
        main.development_origin,
        "--handshake",
        "stdout-v1",
    });
    try std.testing.expect(command == .serve);
    try std.testing.expectEqual(main.RuntimeMode.managed, command.serve.runtime);
}

test "RUNTIME-004 aggregate integration seam remains reachable" {
    try selfTest();
}
