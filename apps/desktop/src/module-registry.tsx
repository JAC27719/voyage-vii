import type { Component } from "solid-js";

import { SystemStatusView } from "./system-status";

export type ModuleDefinition = {
  id: "system";
  path: "/system/status";
  label: string;
  component: Component;
};

export const modules: readonly ModuleDefinition[] = [
  {
    id: "system",
    path: "/system/status",
    label: "System",
    component: SystemStatusView,
  },
];
