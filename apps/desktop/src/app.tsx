import { Navigate, Route, Router } from "@solidjs/router";
import { For } from "solid-js";

import { modules } from "./module-registry";

export function App() {
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
        <Router>
          <Route
            path="/"
            component={() => <Navigate href="/system/status" />}
          />
          <For each={modules}>
            {(module) => (
              <Route path={module.path} component={module.component} />
            )}
          </For>
        </Router>
      </section>
    </div>
  );
}
