import "server-only";
import { cookies } from "next/headers";
import { SESSION_COOKIE_NAME } from "./constants";
import { DashboardSessionPayload, verifySessionToken } from "./jwt";

/**
 * Server-only session read. Used in layouts/pages (RSC) — never in a
 * component that could ship to the client, since the raw JWT itself must
 * stay in the httpOnly cookie only. Prefer this (plus a fresh call to
 * GET /auth/me where profile fields are needed) over trusting anything the
 * client claims about its own role.
 */
export async function getSession(): Promise<DashboardSessionPayload | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE_NAME)?.value;
  if (!token) return null;
  return verifySessionToken(token);
}

export async function getSessionToken(): Promise<string | null> {
  const cookieStore = await cookies();
  return cookieStore.get(SESSION_COOKIE_NAME)?.value ?? null;
}
