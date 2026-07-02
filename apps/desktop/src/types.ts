export type RuntimeState =
  "launching" | "connected" | "restarting" | "failed" | "stopping";

export type RuntimeSnapshot = {
  generation: number;
  state: RuntimeState;
  connection?: {
    apiUrl: string;
    appToken: string;
  };
  error?: {
    code: string;
    message: string;
  };
};

export type RuntimeChangedEvent = {
  generation: number;
  state: RuntimeState;
};

export type OverallState = "starting" | "ready" | "degraded" | "stopping";

export type ComponentId = "sqlite" | "tigerbeetle";

export type ComponentState =
  "starting" | "healthy" | "retrying" | "unhealthy" | "stopping" | "stopped";

export type ApiErrorCode =
  | "invalid_request"
  | "body_too_large"
  | "unauthorized"
  | "forbidden"
  | "origin_not_allowed"
  | "method_not_allowed"
  | "not_found"
  | "component_not_found"
  | "retry_not_allowed"
  | "service_unavailable"
  | "shutting_down"
  | "internal_error"
  | "sqlite_unavailable"
  | "sqlite_busy"
  | "sqlite_timeout"
  | "tigerbeetle_unavailable"
  | "tigerbeetle_timeout"
  | "native_shutdown_timeout"
  | "runtime_asset_missing"
  | "runtime_asset_invalid"
  | "data_root_locked";

export type SanitizedError = {
  code: ApiErrorCode | string;
  message: string;
};

export type SystemComponent = {
  id: ComponentId;
  displayName: string;
  version: string;
  state: ComponentState;
  lastCheckedAt: string | null;
  attemptCount: number;
  error: SanitizedError | null;
};

export type SystemStatus = {
  schemaVersion: 1;
  requestId: string;
  overallState: OverallState;
  components: SystemComponent[];
};

export type RetryResponse = {
  requestId: string;
  accepted: boolean;
  targets: ComponentId[];
};

export type ApiFailure = {
  status: number;
  requestId: string | null;
  code: string;
  message: string;
};
