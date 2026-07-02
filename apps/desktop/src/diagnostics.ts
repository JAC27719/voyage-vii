import type { ApiFailure, RuntimeSnapshot, SystemStatus } from "./types";

const SECRET_PATTERNS = [
  /Bearer\s+[A-Za-z0-9._~+/=-]+/gi,
  /"appToken"\s*:\s*"[^"]+"/gi,
  /"supervisorToken"\s*:\s*"[^"]+"/gi,
];

export function buildDiagnostics(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
  requestError: ApiFailure | null = null,
): string {
  const lines = [
    "Voyage VII diagnostics",
    `runtime.state=${snapshot.state}`,
    `runtime.generation=${snapshot.generation}`,
  ];

  if (snapshot.error) {
    lines.push(
      `runtime.error=${snapshot.error.code}: ${snapshot.error.message}`,
    );
  }

  if (snapshot.connection) {
    lines.push(`apiUrl=${safeApiUrl(snapshot.connection.apiUrl)}`);
  }

  if (requestError) {
    lines.push(
      `request.error=${requestError.code}; status=${requestError.status}; requestId=${requestError.requestId ?? "none"}; message=${requestError.message}`,
    );
  }

  if (status) {
    lines.push(`requestId=${status.requestId}`);
    lines.push(`overallState=${status.overallState}`);
    for (const component of status.components) {
      lines.push(
        `${component.id}=${component.state}; attempts=${component.attemptCount}; version=${component.version}`,
      );
      if (component.error) {
        lines.push(
          `${component.id}.error=${component.error.code}: ${component.error.message}`,
        );
      }
    }
  }

  return sanitizeDiagnostics(lines.join("\n"));
}

function safeApiUrl(value: string): string {
  try {
    const url = new URL(value);
    return `${url.protocol}//${url.host}`;
  } catch {
    return "invalid";
  }
}

export function sanitizeDiagnostics(value: string): string {
  return SECRET_PATTERNS.reduce(
    (current, pattern) => current.replace(pattern, "[redacted]"),
    value,
  );
}
