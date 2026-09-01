import { jwtVerify } from "jose";
import { JWT_SECRET } from "./constants";

/**
 * Mirrors the backend's `JwtPayload` (backend/src/auth/jwt-payload.interface.ts).
 * `role` is what all role-based checks must use — `accountType` is extra
 * context (which portal a `role: 'user'` account belongs to), never a
 * substitute for `role` on its own.
 */
export interface DashboardSessionPayload {
  sub: string;
  accountType?: "student" | "runner" | "restaurant" | "admin";
  role: "user" | "admin" | "internal_service";
}

let cachedSecret: Uint8Array | null = null;

function getSecretKey(): Uint8Array {
  if (!JWT_SECRET) {
    throw new Error("JWT_SECRET is not set — the dashboard cannot verify backend-issued tokens without it.");
  }
  if (!cachedSecret) {
    cachedSecret = new TextEncoder().encode(JWT_SECRET);
  }
  return cachedSecret;
}

/**
 * Verifies a backend-issued JWT's signature and expiry. Returns null on any
 * failure (invalid signature, expired, malformed) — callers treat that as
 * "not authenticated," never throw-and-crash a request.
 */
export async function verifySessionToken(token: string): Promise<DashboardSessionPayload | null> {
  try {
    const { payload } = await jwtVerify(token, getSecretKey());
    if (typeof payload.sub !== "string" || typeof payload.role !== "string") return null;
    return payload as unknown as DashboardSessionPayload;
  } catch {
    return null;
  }
}
