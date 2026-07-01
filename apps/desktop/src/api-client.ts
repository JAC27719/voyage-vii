import type {
  ApiFailure,
  ComponentId,
  RetryResponse,
  SystemStatus,
} from "./types";

const HTTP_TIMEOUT_MS = 10_000;

type FetchLike = typeof fetch;

export class SystemApiClient {
  readonly #apiUrl: string;
  readonly #appToken: string;
  readonly #fetch: FetchLike;

  constructor(apiUrl: string, appToken: string, fetcher: FetchLike = fetch) {
    this.#apiUrl = apiUrl.replace(/\/$/, "");
    this.#appToken = appToken;
    this.#fetch = fetcher;
  }

  async status(signal?: AbortSignal): Promise<SystemStatus> {
    return await this.#request<SystemStatus>(
      "GET",
      "/api/v1/system/status",
      signal,
    );
  }

  async retry(
    component: ComponentId,
    signal?: AbortSignal,
  ): Promise<RetryResponse> {
    return await this.#request<RetryResponse>(
      "POST",
      `/api/v1/system/components/${component}/retry`,
      signal,
    );
  }

  async retryAll(signal?: AbortSignal): Promise<RetryResponse> {
    return await this.#request<RetryResponse>(
      "POST",
      "/api/v1/system/retry",
      signal,
    );
  }

  async #request<T>(
    method: "GET" | "POST",
    path: string,
    outerSignal?: AbortSignal,
  ): Promise<T> {
    const controller = new AbortController();
    const timeout = window.setTimeout(
      () => controller.abort(),
      HTTP_TIMEOUT_MS,
    );
    const abort = () => controller.abort();
    outerSignal?.addEventListener("abort", abort, { once: true });

    try {
      const response = await this.#fetch(`${this.#apiUrl}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.#appToken}`,
          Accept: "application/json",
        },
        signal: controller.signal,
      });
      const requestId = response.headers.get("X-Request-Id");
      const body = await readJson(response);
      if (!response.ok) {
        throw normalizeFailure(response.status, requestId, body);
      }
      return body as T;
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        throw {
          status: 0,
          requestId: null,
          code: "request_timeout",
          message: "The API request timed out.",
        } satisfies ApiFailure;
      }
      throw error;
    } finally {
      window.clearTimeout(timeout);
      outerSignal?.removeEventListener("abort", abort);
    }
  }
}

async function readJson(response: Response): Promise<unknown> {
  const text = await response.text();
  if (text.trim() === "") {
    return {};
  }
  return JSON.parse(text) as unknown;
}

function normalizeFailure(
  status: number,
  requestId: string | null,
  body: unknown,
): ApiFailure {
  if (isErrorBody(body)) {
    return {
      status,
      requestId: body.error.requestId || requestId,
      code: body.error.code,
      message: body.error.message,
    };
  }
  return {
    status,
    requestId,
    code: "service_unavailable",
    message: "The API request failed.",
  };
}

function isErrorBody(
  body: unknown,
): body is { error: { code: string; message: string; requestId: string } } {
  if (!body || typeof body !== "object" || !("error" in body)) {
    return false;
  }
  const error = (body as { error: unknown }).error;
  return (
    !!error &&
    typeof error === "object" &&
    typeof (error as { code?: unknown }).code === "string" &&
    typeof (error as { message?: unknown }).message === "string" &&
    typeof (error as { requestId?: unknown }).requestId === "string"
  );
}
