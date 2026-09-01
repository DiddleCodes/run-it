import { NextRequest, NextResponse } from "next/server";
import { BACKEND_URL } from "@/lib/auth/constants";
import { getSessionToken } from "@/lib/auth/session";

/**
 * Generic authenticated pass-through to the NestJS backend. Every route the
 * backend exposes already enforces its own guards (JwtAuthGuard,
 * assertCanActAsVendor, ownership checks, ...) — this proxy adds no
 * privilege beyond "attach the caller's own session token," it exists only
 * so the browser never learns BACKEND_URL or handles a raw JWT (the token
 * lives in the httpOnly cookie server-side only). Direct S3 PUTs from the
 * browser for presigned uploads are the one deliberate exception to "the
 * browser never talks past this proxy."
 */
async function handle(req: NextRequest, context: { params: Promise<{ path: string[] }> }) {
  const { path } = await context.params;
  const token = await getSessionToken();

  const search = req.nextUrl.search;
  const backendUrl = `${BACKEND_URL}/${path.join("/")}${search}`;

  const hasBody = !["GET", "HEAD"].includes(req.method);
  const body = hasBody ? await req.text() : undefined;

  const res = await fetch(backendUrl, {
    method: req.method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body,
    cache: "no-store",
  });

  const text = await res.text();
  return new NextResponse(text, {
    status: res.status,
    headers: { "Content-Type": res.headers.get("content-type") ?? "application/json" },
  });
}

export { handle as DELETE, handle as GET, handle as PATCH, handle as POST };
