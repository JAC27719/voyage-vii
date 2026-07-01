import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

import type { RuntimeChangedEvent, RuntimeSnapshot } from "./types";

export const fallbackSnapshot: RuntimeSnapshot = {
  generation: 0,
  state: "launching",
};

export async function getRuntimeSnapshot(): Promise<RuntimeSnapshot> {
  try {
    return await invoke<RuntimeSnapshot>("get_runtime_snapshot");
  } catch {
    return fallbackSnapshot;
  }
}

export async function openLogs(): Promise<void> {
  await invoke("open_logs");
}

export async function listenRuntimeChanged(
  handler: (event: RuntimeChangedEvent) => void,
): Promise<() => void> {
  return await listen<RuntimeChangedEvent>(
    "voyage-vii://runtime-changed",
    (event) => {
      handler(event.payload);
    },
  );
}
