const runtime_tigerbeetle = @import("runtime_tigerbeetle");

test "RUNTIME-003 focused runtime seam self-test" {
    try runtime_tigerbeetle.selfTest();
}
