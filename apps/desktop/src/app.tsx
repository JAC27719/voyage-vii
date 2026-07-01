import { invoke } from "@tauri-apps/api/core";
import { createResource } from "solid-js";

type RuntimeSnapshot = {
  generation: number;
  state: "launching" | "connected" | "restarting" | "failed" | "stopping";
  connection?: {
    apiUrl: string;
    appToken: string;
  };
  error?: {
    code: string;
    message: string;
  };
};

const fallbackSnapshot: RuntimeSnapshot = {
  generation: 0,
  state: "launching",
};

async function getRuntimeSnapshot(): Promise<RuntimeSnapshot> {
  try {
    return await invoke<RuntimeSnapshot>("get_runtime_snapshot");
  } catch {
    return fallbackSnapshot;
  }
}

export function App() {
  const [snapshot] = createResource(getRuntimeSnapshot);

  return (
    <main class="app-shell">
      <aside class="sidebar" aria-label="Primary">
        <div class="brand-mark">VII</div>
      </aside>
      <section class="workspace" aria-live="polite">
        <div class="status-line">
          <span
            class="status-dot"
            data-state={snapshot()?.state ?? "launching"}
          />
          <span>{snapshot()?.state ?? "launching"}</span>
        </div>
      </section>
    </main>
  );
}
