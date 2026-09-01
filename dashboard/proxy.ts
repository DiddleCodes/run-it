import { NextRequest, NextResponse } from "next/server";
import { SESSION_COOKIE_NAME } from "@/lib/auth/constants";
import { verifySessionToken } from "@/lib/auth/jwt";

/**
 * Server-verified role guard. Runs on every request to a protected path and
 * checks the JWT's signature and role/accountType claims — nothing here
 * trusts anything the client sends other than the httpOnly cookie itself.
 *
 * A restaurant account must never even discover /admin exists: a role
 * mismatch redirects to the caller's own portal home, never to /login (that
 * would leak "there's a distinct thing here you're not allowed into").
 */
export async function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;
  const token = req.cookies.get(SESSION_COOKIE_NAME)?.value;
  const session = token ? await verifySessionToken(token) : null;

  if (!session) {
    const loginUrl = new URL("/login", req.url);
    return NextResponse.redirect(loginUrl);
  }

  const isAdmin = session.role === "admin";
  const isRestaurant = session.accountType === "restaurant";

  if (pathname.startsWith("/admin") && !isAdmin) {
    return NextResponse.redirect(new URL(isRestaurant ? "/restaurant/overview" : "/login", req.url));
  }

  if (pathname.startsWith("/restaurant") && !isRestaurant) {
    return NextResponse.redirect(new URL(isAdmin ? "/admin/overview" : "/login", req.url));
  }

  return NextResponse.next();
}

export const config = {
  // Excludes the public auth pages, API routes, Next internals, and — via
  // the trailing `.*\..*` — any request for a static file under public/
  // (images, icons, manifest.json, ...). Without that last clause, a public
  // asset referenced from an unauthenticated page (e.g. the login page's
  // logo) 307s to /login instead of loading.
  matcher: ["/((?!login|forgot-password|reset-password|api|_next/static|_next/image|.*\\..*).*)"],
};
