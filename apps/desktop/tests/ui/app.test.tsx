import "@testing-library/jest-dom/vitest";
import { fireEvent, render, screen } from "@solidjs/testing-library";
import { describe, expect, it, vi } from "vitest";

import { App } from "../../src/app";

vi.mock("../../src/module-registry", () => ({
  modules: [
    {
      id: "system",
      path: "/system/status",
      label: "System",
      component: () => <div>Diagnostics page</div>,
    },
  ],
}));

vi.mock("../../src/startup", () => ({
  StartupView: (props: { onComplete?: () => void }) => (
    <button type="button" onClick={() => props.onComplete?.()}>
      Startup gate
    </button>
  ),
}));

describe("App", () => {
  it("shows startup before diagnostics even when opened on diagnostics URL", async () => {
    window.history.pushState({}, "", "/system/status");

    render(() => <App />);

    expect(screen.getByRole("button", { name: "Startup gate" })).toBeInTheDocument();
    expect(screen.queryByText("Diagnostics page")).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Startup gate" }));

    expect(await screen.findByText("Diagnostics page")).toBeInTheDocument();
  });
});
