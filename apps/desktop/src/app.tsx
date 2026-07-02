import { Navigate, Route, Router } from "@solidjs/router";
import { For } from "solid-js";

import { modules } from "./module-registry";
import type { ModuleDefinition } from "./module-registry";
import { StartupView } from "./startup";

export function App() {
  return (
    <Router>
      <Route path="/" component={() => <Navigate href="/startup" />} />
      <Route path="/startup" component={StartupView} />
      <For each={modules}>
        {(module) => (
          <Route
            path={module.path}
            component={() => <ModuleShell module={module} />}
          />
        )}
      </For>
    </Router>
  );
}

function ModuleShell(props: { module: ModuleDefinition }) {
  const Module = props.module.component;

  return (
    <div class="app-shell">
      <aside class="sidebar" aria-label="Primary">
        <div class="brand-mark" aria-label="Voyage VII">
          VII
        </div>
        <nav aria-label="Modules">
          <For each={modules}>
            {(module) => (
              <a href={module.path} aria-current="page">
                {module.label}
              </a>
            )}
          </For>
        </nav>
      </aside>
      <section class="workspace">
        <Module />
      </section>
    </div>
  );
}
