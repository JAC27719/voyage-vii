import {
  For,
  Show,
  createEffect,
  createMemo,
  createSignal,
  onCleanup,
  onMount,
  untrack,
} from "solid-js";

import { SystemApiClient } from "./api-client";
import { buildDiagnostics } from "./diagnostics";
import {
  fallbackSnapshot,
  getRuntimeSnapshot,
  listenRuntimeChanged,
  openLogs,
} from "./runtime-bridge";
import type {
  ApiFailure,
  ComponentId,
  ComponentState,
  RuntimeSnapshot,
  SystemComponent,
  SystemStatus,
} from "./types";

const FAST_POLL_MS = 1_000;
const HEALTHY_POLL_MS = 10_000;

export function SystemStatusView() {
  const [snapshot, setSnapshot] =
    createSignal<RuntimeSnapshot>(fallbackSnapshot);
  const [status, setStatus] = createSignal<SystemStatus | null>(null);
  const [notice, setNotice] = createSignal("Starting runtime supervision.");
  const [requestError, setRequestError] = createSignal<ApiFailure | null>(null);
  const [copyState, setCopyState] = createSignal<"idle" | "copied" | "failed">(
    "idle",
  );
  const [clientReady, setClientReady] = createSignal(false);
  const [statusInFlight, setStatusInFlight] = createSignal(false);
  const [retryInFlight, setRetryInFlight] = createSignal(false);

  let client: SystemApiClient | null = null;
  let timer: number | undefined;
  let currentAbort: AbortController | undefined;
  let runtimeUnlisten: (() => void) | undefined;
  let disposed = false;

  const summary = createMemo(() =>
    summarize(snapshot(), status(), requestError()),
  );
  const pollMs = createMemo(() => pollingInterval(snapshot(), status()));
  const actionsDisabled = createMemo(
    () => !clientReady() || statusInFlight() || retryInFlight(),
  );

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
      setClientReady(true);
    } else {
      client = null;
      setClientReady(false);
      setStatus(null);
    }
  };

  const fetchStatus = async (
    reason: "poll" | "generation" | "retry" | "401",
  ) => {
    if (!client) {
      return;
    }
    const canAbortObsolete = reason === "generation" || reason === "401";
    if (statusInFlight() && !canAbortObsolete) {
      return;
    }
    currentAbort?.abort();
    setStatusInFlight(true);
    const abort = new AbortController();
    const requestClient = client;
    currentAbort = abort;
    try {
      const next = await requestClient.status(abort.signal);
      if (!disposed && !abort.signal.aborted && client === requestClient) {
        setStatus(next);
        setRequestError(null);
        setNotice(
          reason === "retry" ? "Retry request accepted." : "Status updated.",
        );
      }
    } catch (error) {
      if (abort.signal.aborted) {
        return;
      }
      const failure = asFailure(error);
      if (!disposed) {
        setRequestError(failure);
        setNotice(failure.message);
      }
      if (failure.status === 401 && reason !== "401") {
        await refreshSnapshot();
      }
    } finally {
      if (currentAbort === abort) {
        setStatusInFlight(false);
        currentAbort = undefined;
      }
    }
  };

  const schedule = () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      void untrack(() => fetchStatus("poll")).finally(schedule);
    }, pollMs());
  };

  const retry = async (target: ComponentId | "all") => {
    if (!client || retryInFlight() || statusInFlight()) {
      return;
    }
    setRetryInFlight(true);
    const abort = new AbortController();
    try {
      const response =
        target === "all"
          ? await client.retryAll(abort.signal)
          : await client.retry(target, abort.signal);
      setNotice(
        response.accepted
          ? `Retry requested for ${response.targets.join(", ")}.`
          : `Retry skipped for ${response.targets.join(", ")}.`,
      );
      setRetryInFlight(false);
      await fetchStatus("retry");
    } catch (error) {
      const failure = asFailure(error);
      setRequestError(failure);
      setNotice(failure.message);
      if (failure.status === 401) {
        await refreshSnapshot();
      }
    } finally {
      setRetryInFlight(false);
    }
  };

  const copyDiagnostics = async () => {
    try {
      await navigator.clipboard.writeText(
        buildDiagnostics(snapshot(), status(), requestError()),
      );
      setCopyState("copied");
      setNotice("Diagnostics copied.");
    } catch {
      setCopyState("failed");
      setNotice("Diagnostics could not be copied.");
    }
  };

  onMount(() => {
    void refreshSnapshot().then(() => untrack(() => fetchStatus("generation")));
    void listenRuntimeChanged((event) => {
      void event;
      void refreshSnapshot().then(() =>
        untrack(() => fetchStatus("generation")),
      );
    }).then((unlisten) => {
      if (disposed) {
        unlisten();
      } else {
        runtimeUnlisten = unlisten;
      }
    });
  });

  createEffect(() => {
    const runtimeState = snapshot().state;
    const overallState = status()?.overallState;
    void runtimeState;
    void overallState;
    schedule();
  });

  onCleanup(() => {
    disposed = true;
    window.clearTimeout(timer);
    currentAbort?.abort();
    runtimeUnlisten?.();
  });

  return (
    <main class="status-page" aria-labelledby="status-title">
      <section class="status-hero" aria-live="polite">
        <div>
          <p class="eyebrow">System</p>
          <h1 id="status-title">Runtime Status</h1>
          <p>{summary()}</p>
        </div>
        <div class="toolbar" aria-label="System actions">
          <button
            type="button"
            onClick={() => void retry("all")}
            disabled={actionsDisabled()}
          >
            Retry all
          </button>
          <button type="button" onClick={() => void openLogs()}>
            Open logs
          </button>
          <button type="button" onClick={() => void copyDiagnostics()}>
            Copy diagnostics
          </button>
        </div>
      </section>

      <section class="summary-grid" aria-label="Runtime summary">
        <Metric
          label="Runtime"
          value={formatRuntime(snapshot().state)}
          tone={snapshotTone(snapshot().state)}
        />
        <Metric
          label="API"
          value={status()?.overallState ?? "waiting"}
          tone={overallTone(status()?.overallState)}
        />
        <Metric
          label="Generation"
          value={String(snapshot().generation)}
          tone="neutral"
        />
      </section>

      <Show when={requestError()}>
        {(error) => (
          <section class="notice notice-error" role="status">
            <strong>{error().code}</strong>
            <span>{error().message}</span>
            <Show when={error().requestId}>
              <small>Request {error().requestId}</small>
            </Show>
          </section>
        )}
      </Show>

      <section class="component-grid" aria-label="Components">
        <For each={componentsFor(status())}>
          {(component) => (
            <article class="component-card" data-state={component.state}>
              <div>
                <h2>{component.displayName}</h2>
                <p>{component.version}</p>
              </div>
              <span class="state-badge" data-state={component.state}>
                {formatComponentState(component.state)}
              </span>
              <dl>
                <div>
                  <dt>Attempts</dt>
                  <dd>{component.attemptCount}</dd>
                </div>
                <div>
                  <dt>Last checked</dt>
                  <dd>{formatDate(component.lastCheckedAt)}</dd>
                </div>
              </dl>
              <Show when={component.error}>
                {(error) => (
                  <p class="component-error">
                    {error().code}: {error().message}
                  </p>
                )}
              </Show>
              <button
                type="button"
                onClick={() => void retry(component.id)}
                disabled={actionsDisabled() || component.state === "healthy"}
              >
                Retry
              </button>
            </article>
          )}
        </For>
      </section>

      <p class="sr-status" role="status" aria-live="polite">
        {notice()} {copyState() === "copied" ? "Copied." : ""}
      </p>
    </main>
  );
}

function Metric(props: { label: string; value: string; tone: Tone }) {
  return (
    <div class="metric" data-tone={props.tone}>
      <span>{props.label}</span>
      <strong>{props.value}</strong>
    </div>
  );
}

type Tone = "neutral" | "good" | "warn" | "bad";

function summarize(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
  error: ApiFailure | null,
): string {
  if (snapshot.state === "failed") {
    return snapshot.error?.message ?? "Runtime supervision failed.";
  }
  if (!snapshot.connection) {
    return "Waiting for the managed API handshake.";
  }
  if (error) {
    return `The API reported ${error.code}.`;
  }
  if (!status) {
    return "Connected to the API. Waiting for component status.";
  }
  if (status.overallState === "ready") {
    return "SQLite and TigerBeetle are healthy.";
  }
  if (status.overallState === "degraded") {
    return "One or more runtime components need attention.";
  }
  return "Runtime components are still starting.";
}

function componentsFor(status: SystemStatus | null): SystemComponent[] {
  return (
    status?.components ?? [
      placeholder("sqlite", "SQLite"),
      placeholder("tigerbeetle", "TigerBeetle"),
    ]
  );
}

function placeholder(id: ComponentId, displayName: string): SystemComponent {
  return {
    id,
    displayName,
    version: "pending",
    state: "starting",
    lastCheckedAt: null,
    attemptCount: 0,
    error: null,
  };
}

function pollingInterval(
  snapshot: RuntimeSnapshot,
  status: SystemStatus | null,
): number {
  if (snapshot.state === "launching" || snapshot.state === "restarting") {
    return FAST_POLL_MS;
  }
  if (!status || status.overallState !== "ready") {
    return FAST_POLL_MS;
  }
  if (status.components.some((component) => component.state !== "healthy")) {
    return FAST_POLL_MS;
  }
  return HEALTHY_POLL_MS;
}

function asFailure(error: unknown): ApiFailure {
  if (isFailure(error)) {
    return error;
  }
  if (error instanceof Error) {
    return {
      status: 0,
      requestId: null,
      code: "status_fetch_failed",
      message: `Runtime handshake succeeded, but authenticated status could not be fetched: ${error.message}`,
    };
  }
  return {
    status: 0,
    requestId: null,
    code: "status_fetch_failed",
    message:
      "Runtime handshake succeeded, but authenticated status could not be fetched.",
  };
}

function isFailure(error: unknown): error is ApiFailure {
  return (
    !!error &&
    typeof error === "object" &&
    typeof (error as ApiFailure).status === "number" &&
    typeof (error as ApiFailure).code === "string" &&
    typeof (error as ApiFailure).message === "string"
  );
}

function formatRuntime(state: RuntimeSnapshot["state"]) {
  return state.replace(/^\w/, (value) => value.toUpperCase());
}

function formatComponentState(state: ComponentState) {
  return state.replace(/^\w/, (value) => value.toUpperCase());
}

function formatDate(value: string | null): string {
  if (!value) {
    return "Not yet";
  }
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "medium",
  }).format(new Date(value));
}

function snapshotTone(state: RuntimeSnapshot["state"]): Tone {
  if (state === "connected") {
    return "good";
  }
  if (state === "failed") {
    return "bad";
  }
  if (state === "restarting") {
    return "warn";
  }
  return "neutral";
}

function overallTone(state: SystemStatus["overallState"] | undefined): Tone {
  if (state === "ready") {
    return "good";
  }
  if (state === "degraded") {
    return "bad";
  }
  if (state === "stopping") {
    return "warn";
  }
  return "neutral";
}
