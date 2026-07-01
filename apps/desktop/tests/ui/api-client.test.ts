import { describe, expect, it, vi } from "vitest";

import { SystemApiClient } from "../../src/api-client";

function jsonResponse(
  body: unknown,
  init: ResponseInit & { requestId?: string } = {},
) {
  const headers = new Headers(init.headers);
  if (init.requestId) {
    headers.set("X-Request-Id", init.requestId);
  }
  return new Response(JSON.stringify(body), {
    ...init,
    headers,
  });
}

describe("SystemApiClient", () => {
  it("adds bearer auth, captures status JSON, and keeps request IDs available on errors", async () => {
    const fetcher = vi
      .fn()
      .mockResolvedValueOnce(
        jsonResponse(
          {
            schemaVersion: 1,
            requestId: "req-status",
            overallState: "ready",
            components: [],
          },
          { status: 200, requestId: "req-status" },
        ),
      )
      .mockResolvedValueOnce(
        jsonResponse(
          {
            error: {
              code: "unauthorized",
              message: "Unauthorized.",
              requestId: "req-401",
            },
          },
          { status: 401, requestId: "req-401" },
        ),
      );

    const client = new SystemApiClient(
      "http://127.0.0.1:7800/",
      "app-token",
      fetcher,
    );
    await expect(client.status()).resolves.toMatchObject({
      requestId: "req-status",
      overallState: "ready",
    });

    expect(fetcher).toHaveBeenCalledWith(
      "http://127.0.0.1:7800/api/v1/system/status",
      expect.objectContaining({
        method: "GET",
        headers: expect.objectContaining({
          Authorization: "Bearer app-token",
        }),
      }),
    );

    await expect(client.status()).rejects.toMatchObject({
      status: 401,
      requestId: "req-401",
      code: "unauthorized",
    });
  });

  it("does not replay retry mutations after a failure", async () => {
    const fetcher = vi.fn().mockResolvedValue(
      jsonResponse(
        {
          error: {
            code: "unauthorized",
            message: "Unauthorized.",
            requestId: "req-retry",
          },
        },
        { status: 401, requestId: "req-retry" },
      ),
    );
    const client = new SystemApiClient(
      "http://127.0.0.1:7800",
      "app-token",
      fetcher,
    );

    await expect(client.retry("sqlite")).rejects.toMatchObject({
      status: 401,
    });
    expect(fetcher).toHaveBeenCalledTimes(1);
    expect(fetcher).toHaveBeenCalledWith(
      "http://127.0.0.1:7800/api/v1/system/components/sqlite/retry",
      expect.objectContaining({ method: "POST" }),
    );
  });
});
