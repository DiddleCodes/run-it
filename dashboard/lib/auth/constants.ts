export const SESSION_COOKIE_NAME = "runit_dashboard_session";

// Server-only. The Next.js server is the only thing that ever talks to the
// NestJS backend — the browser never sees this URL or the JWT it returns.
export const BACKEND_URL = process.env.BACKEND_URL ?? "http://localhost:3000";

// Must be the exact same value as the backend's JWT_SECRET (see
// backend/.env) — this app only ever verifies tokens the backend signed, it
// never signs its own.
export const JWT_SECRET = process.env.JWT_SECRET ?? "";
