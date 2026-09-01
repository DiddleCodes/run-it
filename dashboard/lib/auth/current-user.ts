import "server-only";
import { backendFetch } from "../api/backend-client";
import { getSessionToken } from "./session";

export interface CurrentUser {
  id: string;
  email: string | null;
  name: string | null;
  accountType: string;
}

/** Fetches the caller's real profile from the backend — never fabricated. Returns null if there's no valid session. */
export async function getCurrentUser(): Promise<CurrentUser | null> {
  const token = await getSessionToken();
  if (!token) return null;
  try {
    return await backendFetch<CurrentUser>("/auth/me", { token });
  } catch {
    return null;
  }
}
