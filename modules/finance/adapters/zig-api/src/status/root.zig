const std = @import("std");

pub const schema_version = 1;
pub const sqlite_version = "3.53.3";
pub const tigerbeetle_version = "0.17.7";

pub const OverallState = enum {
    starting,
    ready,
    degraded,
    stopping,

    pub fn json(self: OverallState) []const u8 {
        return @tagName(self);
    }
};

pub const ComponentId = enum {
    sqlite,
    tigerbeetle,

    pub fn parse(value: []const u8) ?ComponentId {
        if (std.mem.eql(u8, value, "sqlite")) return .sqlite;
        if (std.mem.eql(u8, value, "tigerbeetle")) return .tigerbeetle;
        return null;
    }

    pub fn json(self: ComponentId) []const u8 {
        return @tagName(self);
    }

    pub fn displayName(self: ComponentId) []const u8 {
        return switch (self) {
            .sqlite => "SQLite",
            .tigerbeetle => "TigerBeetle",
        };
    }

    pub fn version(self: ComponentId) []const u8 {
        return switch (self) {
            .sqlite => sqlite_version,
            .tigerbeetle => tigerbeetle_version,
        };
    }
};

pub const ComponentState = enum {
    starting,
    healthy,
    retrying,
    unhealthy,
    stopping,
    stopped,

    pub fn json(self: ComponentState) []const u8 {
        return @tagName(self);
    }
};

pub const ErrorCode = enum {
    invalid_request,
    body_too_large,
    unauthorized,
    forbidden,
    origin_not_allowed,
    method_not_allowed,
    not_found,
    component_not_found,
    retry_not_allowed,
    service_unavailable,
    shutting_down,
    internal_error,
    sqlite_unavailable,
    sqlite_busy,
    sqlite_timeout,
    tigerbeetle_unavailable,
    tigerbeetle_timeout,
    native_shutdown_timeout,
    runtime_asset_missing,
    runtime_asset_invalid,
    data_root_locked,

    pub fn json(self: ErrorCode) []const u8 {
        return @tagName(self);
    }
};

pub const SanitizedError = struct {
    code: ErrorCode,
    message: []const u8,
};

pub const ComponentStatus = struct {
    id: ComponentId,
    state: ComponentState,
    last_checked_at: ?[]const u8 = null,
    attempt_count: u32 = 0,
    diagnostic: ?SanitizedError = null,
    retry_active: bool = false,
};

pub const Snapshot = struct {
    overall_state: OverallState,
    sqlite: ComponentStatus,
    tigerbeetle: ComponentStatus,

    pub fn init() Snapshot {
        return .{
            .overall_state = .starting,
            .sqlite = .{ .id = .sqlite, .state = .starting },
            .tigerbeetle = .{ .id = .tigerbeetle, .state = .starting },
        };
    }

    pub fn isReady(self: Snapshot) bool {
        return self.overall_state == .ready and
            self.sqlite.state == .healthy and
            self.tigerbeetle.state == .healthy;
    }

    pub fn component(self: *Snapshot, id: ComponentId) *ComponentStatus {
        return switch (id) {
            .sqlite => &self.sqlite,
            .tigerbeetle => &self.tigerbeetle,
        };
    }

    pub fn componentConst(self: Snapshot, id: ComponentId) ComponentStatus {
        return switch (id) {
            .sqlite => self.sqlite,
            .tigerbeetle => self.tigerbeetle,
        };
    }

    pub fn markRetry(self: *Snapshot, id: ComponentId) bool {
        if (self.overall_state == .stopping) return false;
        const target = self.component(id);
        if (target.state == .healthy or
            target.state == .stopping or
            target.state == .stopped or
            target.retry_active) return false;
        target.retry_active = true;
        target.state = .retrying;
        target.attempt_count += 1;
        self.overall_state = .degraded;
        return true;
    }

    pub fn markStopping(self: *Snapshot) bool {
        if (self.overall_state == .stopping) return false;
        self.overall_state = .stopping;
        self.sqlite.state = .stopping;
        self.tigerbeetle.state = .stopping;
        return true;
    }
};

pub const poll_transition_ms: u32 = 1_000;
pub const poll_healthy_ms: u32 = 10_000;

pub fn pollIntervalMs(snapshot: Snapshot) u32 {
    if (snapshot.isReady()) return poll_healthy_ms;
    return poll_transition_ms;
}

pub fn messageFor(code: ErrorCode) []const u8 {
    return switch (code) {
        .invalid_request => "Invalid request.",
        .body_too_large => "Request body is too large.",
        .unauthorized => "Authentication is required.",
        .forbidden => "The token is not allowed to perform this action.",
        .origin_not_allowed => "Origin is not allowed.",
        .method_not_allowed => "Method is not allowed.",
        .not_found => "Route was not found.",
        .component_not_found => "Component was not found.",
        .retry_not_allowed => "Retry is not allowed.",
        .service_unavailable => "Service is unavailable.",
        .shutting_down => "The service is shutting down.",
        .internal_error => "Internal error.",
        .sqlite_unavailable => "SQLite is unavailable.",
        .sqlite_busy => "SQLite is busy.",
        .sqlite_timeout => "SQLite timed out.",
        .tigerbeetle_unavailable => "TigerBeetle is unavailable.",
        .tigerbeetle_timeout => "TigerBeetle timed out.",
        .native_shutdown_timeout => "Native shutdown timed out.",
        .runtime_asset_missing => "Runtime asset is missing.",
        .runtime_asset_invalid => "Runtime asset is invalid.",
        .data_root_locked => "Data root is locked.",
    };
}

pub fn selfTest() !void {
    if (schema_version != 1) return error.InvalidStatusSchema;
    if (poll_transition_ms != 1_000) return error.InvalidStatusPollInterval;
    if (poll_healthy_ms != 10_000) return error.InvalidStatusPollInterval;
    var snapshot = Snapshot.init();
    if (snapshot.isReady()) return error.InvalidStatusState;
    _ = snapshot.markRetry(.sqlite);
    if (snapshot.sqlite.state != .retrying) return error.InvalidStatusState;
    if (snapshot.markRetry(.sqlite)) return error.InvalidStatusState;
    if (!snapshot.markStopping()) return error.InvalidStatusState;
    if (snapshot.markRetry(.tigerbeetle)) return error.InvalidStatusState;
    if (snapshot.markStopping()) return error.InvalidStatusState;
}

test "API-004 status snapshot readiness retry and shutdown states are stable" {
    var snapshot = Snapshot.init();
    try std.testing.expect(!snapshot.isReady());
    try std.testing.expectEqual(@as(u32, poll_transition_ms), pollIntervalMs(snapshot));

    snapshot.overall_state = .ready;
    snapshot.sqlite.state = .healthy;
    snapshot.tigerbeetle.state = .healthy;
    try std.testing.expect(snapshot.isReady());
    try std.testing.expectEqual(@as(u32, poll_healthy_ms), pollIntervalMs(snapshot));

    try std.testing.expect(!snapshot.markRetry(.sqlite));
    snapshot.sqlite.state = .unhealthy;
    try std.testing.expect(snapshot.markRetry(.sqlite));
    try std.testing.expect(!snapshot.markRetry(.sqlite));
    try std.testing.expectEqual(@as(u32, 1), snapshot.sqlite.attempt_count);

    try std.testing.expect(snapshot.markStopping());
    try std.testing.expect(!snapshot.markRetry(.tigerbeetle));
    try std.testing.expect(!snapshot.markStopping());
    try std.testing.expectEqual(ComponentState.stopping, snapshot.sqlite.state);
}
