const std = @import("std");

pub const redaction_required = true;
pub const aggregate_budget_bytes: u64 = 50 * 1024 * 1024;
pub const default_segment_budget_bytes: u64 = 5 * 1024 * 1024;
pub const default_segment_count: u8 = 10;
pub const log_file_name = "api.log";

pub const LogError = error{
    SecretRejected,
    InvalidRotationConfig,
};

pub const RotationConfig = struct {
    segment_budget_bytes: u64 = default_segment_budget_bytes,
    segment_count: u8 = default_segment_count,

    pub fn validate(self: RotationConfig) LogError!void {
        if (self.segment_budget_bytes == 0 or self.segment_count == 0) return error.InvalidRotationConfig;
        if (self.segment_budget_bytes * self.segment_count > aggregate_budget_bytes) {
            return error.InvalidRotationConfig;
        }
    }
};

pub const StructuredLogEntry = struct {
    level: []const u8,
    event: []const u8,
    message: []const u8,
    request_id: ?[]const u8 = null,

    pub fn validate(self: StructuredLogEntry) LogError!void {
        try rejectSecretLikeText(self.level);
        try rejectSecretLikeText(self.event);
        try rejectSecretLikeText(self.message);
        if (self.request_id) |request_id| try rejectSecretLikeText(request_id);
    }
};

pub fn writeEntry(writer: anytype, entry: StructuredLogEntry) !void {
    try entry.validate();
    try writer.writeAll("{\"level\":");
    try writeJsonString(writer, entry.level);
    try writer.writeAll(",\"event\":");
    try writeJsonString(writer, entry.event);
    try writer.writeAll(",\"message\":");
    try writeJsonString(writer, entry.message);
    if (entry.request_id) |request_id| {
        try writer.writeAll(",\"requestId\":");
        try writeJsonString(writer, request_id);
    }
    try writer.writeAll("}\n");
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (byte < 0x20) {
                    try writer.print("\\u00{x:0>2}", .{byte});
                } else {
                    try writer.writeByte(byte);
                }
            },
        }
    }
    try writer.writeByte('"');
}

pub fn rotateIfNeeded(dir: std.fs.Dir, config: RotationConfig) !void {
    try config.validate();
    const stat = dir.statFile(log_file_name) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    if (stat.size <= config.segment_budget_bytes) return;

    var index: u8 = config.segment_count - 1;
    while (index > 0) : (index -= 1) {
        var old_buffer: [32]u8 = undefined;
        const old_name = try rotatedName(&old_buffer, index);
        var new_buffer: [32]u8 = undefined;
        const new_name = try rotatedName(&new_buffer, index + 1);
        if (index + 1 >= config.segment_count) {
            dir.deleteFile(old_name) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        } else {
            dir.rename(old_name, new_name) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };
        }
    }
    var first_buffer: [32]u8 = undefined;
    const first_name = try rotatedName(&first_buffer, 1);
    try dir.rename(log_file_name, first_name);
}

fn rotatedName(buffer: []u8, index: u8) ![]u8 {
    return try std.fmt.bufPrint(buffer, "{s}.{d}", .{ log_file_name, index });
}

fn rejectSecretLikeText(value: []const u8) LogError!void {
    const needles = [_][]const u8{
        "authorization",
        "bearer ",
        "token",
        "password",
        "secret",
        "credential",
        "postgres-password-file",
        "select ",
        "insert ",
        "update ",
        "delete ",
    };
    for (needles) |needle| {
        if (std.ascii.indexOfIgnoreCase(value, needle) != null) return error.SecretRejected;
    }
}

pub fn selfTest() !void {
    try (RotationConfig{}).validate();
    try expectLogError(error.InvalidRotationConfig, (RotationConfig{
        .segment_budget_bytes = aggregate_budget_bytes,
        .segment_count = 2,
    }).validate());
    try (StructuredLogEntry{
        .level = "info",
        .event = "runtime.started",
        .message = "component started",
        .request_id = "req-1",
    }).validate();
    try expectLogError(error.SecretRejected, (StructuredLogEntry{
        .level = "info",
        .event = "auth",
        .message = "Authorization: Bearer abc",
    }).validate());

    var buffer: [128]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try writeEntry(stream.writer(), .{
        .level = "info",
        .event = "runtime.started",
        .message = "component started",
        .request_id = "req-1",
    });
    stream.reset();
    try writeEntry(stream.writer(), .{
        .level = "info",
        .event = "runtime.quoted",
        .message = "quoted \"message\"",
    });
}

fn expectLogError(expected: anyerror, actual: anytype) !void {
    if (actual) |_| return error.SelfTestFailed else |err| {
        if (err == expected) return;
        return err;
    }
}

test "runtime logging rotates under the aggregate budget" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = log_file_name, .data = "0123456789" });
    try tmp.dir.writeFile(.{ .sub_path = "api.log.1", .data = "previous" });
    try rotateIfNeeded(tmp.dir, .{ .segment_budget_bytes = 4, .segment_count = 3 });
    try tmp.dir.access("api.log.1", .{});
    try tmp.dir.access("api.log.2", .{});
}
