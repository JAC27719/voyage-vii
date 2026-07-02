import "@testing-library/jest-dom/vitest";
import { render, screen, waitFor } from "@solidjs/testing-library";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { StartupView } from "../../src/startup";
import type {
  RuntimeChangedEvent,
  RuntimeSnapshot,
  SystemStatus,
} from "../../src/types";

let navigate: ReturnType<typeof vi.fn>;
let snapshot: RuntimeSnapshot;
let runtimeListeners: Array<(event: RuntimeChangedEvent) => void>;

vi.mock("@solidjs/router", () => ({
  useNavigate: () => navigate,
}));

vi.mock("../../src/runtime-bridge", () => ({
  fallbackSnapshot: {
    generation: 0,
    state: "failed",
    error: {
      code: "desktop_bridge_unavailable",
      message:
        "Desktop runtime bridge is unavailable. Open Voyage VII in the desktop app to start the managed API.",
    },
  },
  getRuntimeSnapshot: vi.fn(async () => snapshot),
  listenRuntimeChanged: vi.fn(
    async (handler: (event: RuntimeChangedEvent) => void) => {
      runtimeListeners.push(handler);
      return vi.fn();
    },
  ),
}));

const connected: RuntimeSnapshot = {
  generation: 1,
  state: "connected",
  connection: {
    apiUrl: "http://127.0.0.1:7800",
    appToken: "app-token",
  },
};

function status(overrides: Partial<SystemStatus> = {}): SystemStatus {
  return {
    schemaVersion: 1,
    requestId: "req-startup",
    overallState: "ready",
    components: [
      {
        id: "sqlite",
        displayName: "SQLite",
        version: "3.53.3",
        state: "healthy",
        lastCheckedAt: "2026-07-01T10:00:00Z",
        attemptCount: 0,
        error: null,
      },
      {
        id: "tigerbeetle",
        displayName: "TigerBeetle",
        version: "0.17.7",
        state: "healthy",
        lastCheckedAt: "2026-07-01T10:00:00Z",
        attemptCount: 0,
        error: null,
      },
    ],
    ...overrides,
  };
}

function response(body: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("X-Request-Id", "req-startup");
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      ...init,
      headers,
    }),
  );
}

describe("StartupView", () => {
  beforeEach(() => {
    navigate = vi.fn();
    snapshot = { generation: 0, state: "launching" };
    runtimeListeners = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(() => response(status(), { status: 200 })),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it("renders progress and startup messages while the runtime launches", async () => {
    render(() => <StartupView />);

    expect(
      await screen.findByRole("heading", { name: "Starting local runtime" }),
    ).toBeInTheDocument();
    expect(screen.getByRole("progressbar")).toBeInTheDocument();
    expect(screen.getByText("Runtime supervisor")).toBeInTheDocument();
    expect(screen.getByText("Launching local services.")).toBeInTheDocument();
    expect(navigate).not.toHaveBeenCalled();
  });

  it("routes to diagnostics after every managed component is healthy", async () => {
    snapshot = connected;
    render(() => <StartupView />);

    await waitFor(() => {
      expect(navigate).toHaveBeenCalledWith("/system/status", {
        replace: true,
      });
    });
  });

  it("stays on startup while components are still starting", async () => {
    snapshot = connected;
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        response(
          status({
            overallState: "starting",
            components: status().components.map((component) => ({
              ...component,
              state: "starting",
            })),
          }),
          { status: 200 },
        ),
      ),
    );

    render(() => <StartupView />);

    expect(await screen.findByText("SQLite is starting.")).toBeInTheDocument();
    expect(screen.getByText("TigerBeetle is starting.")).toBeInTheDocument();
    expect(navigate).not.toHaveBeenCalled();
  });
});
