import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen, waitFor } from "@solidjs/testing-library";
import axe from "axe-core";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { SystemStatusView } from "../../src/system-status";
import type {
  RuntimeChangedEvent,
  RuntimeSnapshot,
  SystemStatus,
} from "../../src/types";

let snapshot: RuntimeSnapshot;
let runtimeListeners: Array<(event: RuntimeChangedEvent) => void>;
let unlisten: ReturnType<typeof vi.fn>;

vi.mock("../../src/runtime-bridge", () => ({
  fallbackSnapshot: { generation: 0, state: "launching" },
  getRuntimeSnapshot: vi.fn(async () => snapshot),
  listenRuntimeChanged: vi.fn(
    async (handler: (event: RuntimeChangedEvent) => void) => {
      runtimeListeners.push(handler);
      return unlisten;
    },
  ),
  openLogs: vi.fn(async () => undefined),
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
    requestId: "req-1",
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
  headers.set("X-Request-Id", "req-test");
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      ...init,
      headers,
    }),
  );
}

describe("SystemStatusView", () => {
  beforeEach(() => {
    snapshot = connected;
    runtimeListeners = [];
    unlisten = vi.fn();
    vi.stubGlobal(
      "fetch",
      vi.fn(() => response(status(), { status: 200 })),
    );
    Object.assign(navigator, {
      clipboard: {
        writeText: vi.fn(async () => undefined),
      },
    });
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it("renders healthy component state and copies sanitized diagnostics", async () => {
    render(() => <SystemStatusView />);

    expect(
      await screen.findByText("SQLite and TigerBeetle are healthy."),
    ).toBeInTheDocument();
    expect(screen.getByText("SQLite")).toBeInTheDocument();
    expect(screen.getByText("TigerBeetle")).toBeInTheDocument();
    expect(screen.getByText("Runtime Status")).toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Copy diagnostics" }));
    await waitFor(() => {
      expect(navigator.clipboard.writeText).toHaveBeenCalledWith(
        expect.not.stringContaining("app-token"),
      );
    });
  });

  it("has no automated accessibility violations in the healthy state", async () => {
    render(() => <SystemStatusView />);
    await screen.findByText("SQLite and TigerBeetle are healthy.");

    const results = await axe.run(document.body, {
      rules: {
        "color-contrast": { enabled: false },
      },
    });

    expect(results.violations).toEqual([]);
  });

  it("keeps primary actions keyboard reachable", async () => {
    render(() => <SystemStatusView />);
    await screen.findByText("SQLite and TigerBeetle are healthy.");

    const openLogs = screen.getByRole("button", { name: "Open logs" });
    const copyDiagnostics = screen.getByRole("button", {
      name: "Copy diagnostics",
    });
    const retryAll = screen.getByRole("button", { name: "Retry all" });

    openLogs.focus();
    expect(openLogs).toHaveFocus();

    fireEvent.keyDown(openLogs, { key: "Tab" });
    copyDiagnostics.focus();
    expect(copyDiagnostics).toHaveFocus();

    retryAll.focus();
    expect(retryAll).toHaveFocus();
  });

  it("renders degraded state with component errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        response(
          status({
            overallState: "degraded",
            components: [
              status().components[0],
              {
                ...status().components[1],
                state: "unhealthy",
                attemptCount: 3,
                error: {
                  code: "tigerbeetle_timeout",
                  message: "TigerBeetle timed out.",
                },
              },
            ],
          }),
          { status: 200 },
        ),
      ),
    );

    render(() => <SystemStatusView />);

    expect(
      await screen.findByText("One or more runtime components need attention."),
    ).toBeInTheDocument();
    expect(
      screen.getByText("tigerbeetle_timeout: TigerBeetle timed out."),
    ).toBeInTheDocument();
  });

  it("refreshes the runtime snapshot once after a generation change event", async () => {
    const bridge = await import("../../src/runtime-bridge");
    render(() => <SystemStatusView />);
    await screen.findByText("SQLite");

    snapshot = { ...connected, generation: 2 };
    runtimeListeners[0]?.({ generation: 2, state: "connected" });

    await waitFor(() => {
      expect(bridge.getRuntimeSnapshot).toHaveBeenCalledTimes(2);
    });
  });

  it("refreshes the runtime snapshot after same-generation runtime events", async () => {
    const bridge = await import("../../src/runtime-bridge");
    render(() => <SystemStatusView />);
    await screen.findByText("SQLite");

    snapshot = { ...connected, state: "restarting" };
    runtimeListeners[0]?.({ generation: 1, state: "restarting" });

    await waitFor(() => {
      expect(bridge.getRuntimeSnapshot).toHaveBeenCalledTimes(2);
    });
    expect(await screen.findByText("Restarting")).toBeInTheDocument();
  });

  it("aborts obsolete status requests after runtime generation changes", async () => {
    let resolveFirst: (value: Response) => void = () => undefined;
    let firstSignal: AbortSignal | undefined;
    const first = new Promise<Response>((resolve) => {
      resolveFirst = resolve;
    });
    const fetcher = vi
      .fn()
      .mockImplementationOnce((_url: string, init: RequestInit) => {
        firstSignal = init.signal as AbortSignal;
        return first;
      })
      .mockImplementation(() =>
        response(
          status({
            requestId: "req-2",
            components: [
              {
                ...status().components[0],
                attemptCount: 2,
              },
              status().components[1],
            ],
          }),
          { status: 200 },
        ),
      );
    vi.stubGlobal("fetch", fetcher);

    render(() => <SystemStatusView />);
    await waitFor(() => expect(fetcher).toHaveBeenCalledTimes(1));

    snapshot = { ...connected, generation: 2 };
    runtimeListeners[0]?.({ generation: 2, state: "connected" });

    await waitFor(() => expect(firstSignal?.aborted).toBe(true));
    await waitFor(() => expect(fetcher).toHaveBeenCalledTimes(2));

    resolveFirst(
      await response(
        status({
          requestId: "old-req",
          components: [
            {
              ...status().components[0],
              attemptCount: 99,
            },
            status().components[1],
          ],
        }),
        { status: 200 },
      ),
    );

    expect(screen.queryByText("99")).not.toBeInTheDocument();
  });

  it("refreshes snapshot on 401 without replaying retry mutations", async () => {
    const bridge = await import("../../src/runtime-bridge");
    const unhealthy = status({
      overallState: "degraded",
      components: [
        status().components[0],
        {
          ...status().components[1],
          state: "unhealthy",
          error: {
            code: "tigerbeetle_timeout",
            message: "TigerBeetle timed out.",
          },
        },
      ],
    });
    const fetcher = vi
      .fn()
      .mockImplementationOnce(() => response(unhealthy, { status: 200 }))
      .mockImplementationOnce(() =>
        response(
          {
            error: {
              code: "unauthorized",
              message: "Unauthorized.",
              requestId: "req-401",
            },
          },
          { status: 401 },
        ),
      );
    vi.stubGlobal("fetch", fetcher);
    render(() => <SystemStatusView />);
    await screen.findByText("SQLite");

    fireEvent.click(screen.getAllByRole("button", { name: "Retry" })[1]);

    await waitFor(() => {
      expect(bridge.getRuntimeSnapshot).toHaveBeenCalledTimes(2);
    });
    expect(
      fetcher.mock.calls.filter(([url]) =>
        String(url).includes("/api/v1/system/components/tigerbeetle/retry"),
      ),
    ).toHaveLength(1);
  });

  it("polls without overlapping in-flight status requests", async () => {
    vi.useFakeTimers();
    let resolveFirst: (value: Response) => void = () => undefined;
    const first = new Promise<Response>((resolve) => {
      resolveFirst = resolve;
    });
    const fetcher = vi
      .fn()
      .mockReturnValueOnce(first)
      .mockImplementation(() => response(status(), { status: 200 }));
    vi.stubGlobal("fetch", fetcher);

    render(() => <SystemStatusView />);
    await vi.advanceTimersByTimeAsync(2_500);
    expect(fetcher).toHaveBeenCalledTimes(1);

    resolveFirst(await response(status(), { status: 200 }));
    await vi.advanceTimersByTimeAsync(10_000);
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});
