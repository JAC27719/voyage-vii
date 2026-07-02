import { Navigate, Route, Router } from "@solidjs/router";
import { For, Show, createSignal } from "solid-js";

import { modules } from "./module-registry";
import type { ModuleDefinition } from "./module-registry";
import { StartupView } from "./startup";

export function App() {
  const [ready, setReady] = createSignal(false);

  return (
    <Show
      when={ready()}
      fallback={<StartupView onComplete={() => setReady(true)} />}
    >
      <Router>
        <Route path="/" component={() => <Navigate href="/system/status" />} />
        <Route
          path="/startup"
          component={() => <Navigate href="/system/status" />}
        />
        <For each={modules}>
          {(module) => (
            <Route
              path={module.path}
              component={() => <ModuleShell module={module} />}
            />
          )}
        </For>
      </Router>
    </Show>
  );
}

function ModuleShell(props: { module: ModuleDefinition }) {
  // Module definitions come from the static registry, not reactive route state.
  // eslint-disable-next-line solid/reactivity
  const module = props.module;
  const Module = module.component;

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
