import { useNavigate } from "@solidjs/router";
import {
  For,
  Show,
  createEffect,
  createMemo,
  createSignal,
  onCleanup,
  onMount,
} from "solid-js";

import { SystemApiClient } from "./api-client";
import {
  fallbackSnapshot,
  getRuntimeSnapshot,
  listenRuntimeChanged,
} from "./runtime-bridge";
import type {
  ApiFailure,
  RuntimeSnapshot,
  SystemComponent,
  SystemStatus,
} from "./types";

const STARTUP_POLL_MS = 1_000;

type StartupMessage = {
  key: string;
  label: string;
  detail: string;
  state: "waiting" | "active" | "done" | "error";
};

export function StartupView() {
  const navigate = useNavigate();
  const [snapshot, setSnapshot] =
    createSignal<RuntimeSnapshot>(fallbackSnapshot);
  const [status, setStatus] = createSignal<SystemStatus | null>(null);
  const [requestError, setRequestError] = createSignal<ApiFailure | null>(null);
  const [statusInFlight, setStatusInFlight] = createSignal(false);

  let client: SystemApiClient | null = null;
  let timer: number | undefined;
  let disposed = false;
  let unlistenRuntime: (() => void) | undefined;

  const messages = createMemo(() =>
    startupMessages(snapshot(), status(), requestError()),
  );
  const progress = createMemo(() => startupProgress(snapshot(), status()));

  const refreshSnapshot = async () => {
    const next = await getRuntimeSnapshot();
    if (disposed) {
      return;
    }
    setSnapshot(next);
    if (next.connection) {
      client = new SystemApiClient(
        next.connection.apiUrl,
        next.connection.appToken,
      );
    } else {
      client = null;
      setStatus(null);
    }
  };

  const fetchStatus = async () => {
    if (!client || statusInFlight()) {
      return;
    }
    setStatusInFlight(true);
    try {
      const next = await client.status();
      if (!disposed) {
        setStatus(next);
        setRequestError(null);
      }
    } catch (error) {
      if (!disposed) {
        setRequestError(asFailure(error));
      }
    } finally {
      if (!disposed) {
        setStatusInFlight(false);
      }
    }
  };

  const tick = async () => {
    await refreshSnapshot();
    await fetchStatus();
  };

  onMount(() => {
    void tick();
    timer = window.setInterval(() => void tick(), STARTUP_POLL_MS);
    void listenRuntimeChanged(() => {
      void tick();
    }).then((unlisten) => {
      if (disposed) {
        unlisten();
      } else {
        unlistenRuntime = unlisten;
      }
    });
  });

  createEffect(() => {
    if (startupComplete(snapshot(), status())) {
      navigate("/system/status", { replace: true });
    }
  });

  onCleanup(() => {
    disposed = true;
    window.clearInterval(timer);
    unlistenRuntime?.();
  });

  return (
    <main class="startup-page" aria-labelledby="startup-title">
      <section class="startup-panel" aria-live="polite">
        <div class="startup-mark">VII</div>
        <div class="startup-heading">
          <p>Voyage VII</p>
          <h1 id="startup-title">Starting local runtime</h1>
          <span>Preparing the desktop bridge, API, SQLite, and TigerBeetle.</span>
        </div>

        <div class="startup-progress" aria-label="Startup progress">
          <div>
            <span>Startup progress</span>
            <strong>{progress()}%</strong>
          </div>
          <progress value={progress()} max="100">
            {progress()}%
          </progress>
        </div>

        <ol class="startup-stream" aria-label="Startup messages">
          <For each={messages()}>
            {(message) => (
              <li data-state={message.state}>
                <span>{message.label}</span>
                <p>{message.detail}</p>
              </li>
            )}
          </For>
        </ol>

        <Show when={requestError()}>
          {(error) => (
            <div class="startup-error" role="status">
              <strong>{error().code}</strong>
              <span>{error().message}</span>
            </div>
          )}
        </Show>
      </section>
    </main>
  );
}

function startupComplete(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
): boolean {
  return (
    snapshot.state === "connected" &&
    status?.overallState === "ready" &&
    status.components.every((component) => component.state === "healthy")
  );
}

function startupProgress(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
): number {
  if (startupComplete(snapshot, status)) {
    return 100;
  }
  if (snapshot.state === "failed") {
    return 100;
  }

  let progress = snapshot.state === "connected" ? 40 : 18;
  if (status) {
    progress = Math.max(progress, status.overallState === "starting" ? 58 : 70);
    progress += healthyComponent(status.components, "sqlite") ? 14 : 0;
    progress += healthyComponent(status.components, "tigerbeetle") ? 14 : 0;
  }
  return Math.min(progress, 96);
}

function startupMessages(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
  requestError: ApiFailure | null,
): StartupMessage[] {
  const sqlite = component(status, "sqlite");
  const tigerbeetle = component(status, "tigerbeetle");

  return [
    {
      key: "window",
      label: "Desktop window",
      detail: "Startup page is visible.",
      state: "done",
    },
    {
      key: "runtime",
      label: "Runtime supervisor",
      detail: runtimeDetail(snapshot),
      state: runtimeMessageState(snapshot),
    },
    {
      key: "api",
      label: "Managed API",
      detail: apiDetail(snapshot, status, requestError),
      state: apiMessageState(snapshot, status, requestError),
    },
    componentMessage("sqlite", "SQLite", sqlite),
    componentMessage("tigerbeetle", "TigerBeetle", tigerbeetle),
  ];
}

function runtimeDetail(snapshot: RuntimeSnapshot): string {
  if (snapshot.error) {
    return snapshot.error.message;
  }
  switch (snapshot.state) {
    case "connected":
      return "Handshake completed.";
    case "restarting":
      return "Restarting managed runtime.";
    case "stopping":
      return "Runtime is stopping.";
    case "failed":
      return "Runtime supervisor could not start.";
    case "launching":
      return "Launching local services.";
  }
}

function runtimeMessageState(snapshot: RuntimeSnapshot): StartupMessage["state"] {
  if (snapshot.state === "connected") {
    return "done";
  }
  if (snapshot.state === "failed") {
    return "error";
  }
  return "active";
}

function apiDetail(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
  requestError: ApiFailure | null,
): string {
  if (requestError) {
    return requestError.message;
  }
  if (!snapshot.connection) {
    return "Waiting for runtime handshake.";
  }
  if (!status) {
    return "Requesting authenticated status.";
  }
  if (status.overallState === "ready") {
    return "API status is ready.";
  }
  return `API status is ${status.overallState}.`;
}

function apiMessageState(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
  requestError: ApiFailure | null,
): StartupMessage["state"] {
  if (requestError) {
    return "error";
  }
  if (snapshot.connection && status?.overallState === "ready") {
    return "done";
  }
  if (snapshot.connection) {
    return "active";
  }
  return "waiting";
}

function componentMessage(
  id: "sqlite" | "tigerbeetle",
  label: string,
  item: SystemComponent | undefined,
): StartupMessage {
  if (!item) {
    return {
      key: id,
      label,
      detail: "Waiting for API status.",
      state: "waiting",
    };
  }
  if (item.error) {
    return {
      key: id,
      label,
      detail: `${item.error.code}: ${item.error.message}`,
      state: "error",
    };
  }
  return {
    key: id,
    label,
    detail:
      item.state === "healthy"
        ? `${item.displayName} is healthy.`
        : `${item.displayName} is ${item.state}.`,
    state: item.state === "healthy" ? "done" : "active",
  };
}

function component(
  status: SystemStatus | null,
  id: "sqlite" | "tigerbeetle",
): SystemComponent | undefined {
  return status?.components.find((item) => item.id === id);
}

function healthyComponent(
  components: readonly SystemComponent[],
  id: "sqlite" | "tigerbeetle",
): boolean {
  return components.some((item) => item.id === id && item.state === "healthy");
}

function asFailure(error: unknown): ApiFailure {
  if (error && typeof error === "object" && "code" in error) {
    return error as ApiFailure;
  }
  return {
    status: 0,
    requestId: null,
    code: "status_fetch_failed",
    message:
      error instanceof Error
        ? error.message
        : "Runtime status could not be fetched.",
  };
}
