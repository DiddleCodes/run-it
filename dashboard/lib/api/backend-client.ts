import "server-only";
import { BACKEND_URL } from "../auth/constants";

export class BackendApiError extends Error {
  constructor(
    public status: number,
    public body: unknown,
  ) {
    super(typeof body === "object" && body && "message" in body ? String((body as { message: unknown }).message) : "Backend request failed");
  }
}

/**
 * Server-only fetch wrapper for the NestJS backend. The browser never calls
 * the backend directly — every dashboard page/Route Handler goes through
 * this, attaching a bearer token when one is supplied. Callers pass the
 * token explicitly rather than this helper reading cookies itself, since
 * Route Handlers (login/forgot-password) call it *before* any session
 * cookie exists.
 */
export async function backendFetch<T>(
  path: string,
  options: { method?: string; body?: unknown; token?: string } = {},
): Promise<T> {
  const res = await fetch(`${BACKEND_URL}${path}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
    },
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
    cache: "no-store",
  });

  const contentType = res.headers.get("content-type") ?? "";
  const data = contentType.includes("application/json") ? await res.json() : await res.text();

  if (!res.ok) {
    throw new BackendApiError(res.status, data);
  }
  return data as T;
}
