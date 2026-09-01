import { decodeJwt } from "jose";
import { NextRequest, NextResponse } from "next/server";
import { BackendApiError, backendFetch } from "@/lib/api/backend-client";
import { SESSION_COOKIE_NAME } from "@/lib/auth/constants";

interface LoginResponse {
  accessToken: string;
  user: { id: string; email: string | null; name: string | null; accountType: string };
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email : null;
  const password = typeof body?.password === "string" ? body.password : null;

  if (!email || !password) {
    return NextResponse.json({ message: "Email and password are required." }, { status: 400 });
  }

  try {
    const result = await backendFetch<LoginResponse>("/auth/login", {
      method: "POST",
      body: { email, password },
    });

    const claims = decodeJwt(result.accessToken);
    const maxAgeSeconds = typeof claims.exp === "number" ? Math.max(claims.exp - Math.floor(Date.now() / 1000), 0) : 60 * 60 * 24;

    // No token/role in the JSON body — the client only learns the account
    // type, purely to pick which page to redirect to. Real enforcement of
    // what that account is allowed to see is the httpOnly cookie + the
    // server-verified role check in middleware.ts, not this response.
    const response = NextResponse.json({ accountType: result.user.accountType });
    response.cookies.set(SESSION_COOKIE_NAME, result.accessToken, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: maxAgeSeconds,
    });
    return response;
  } catch (err) {
    if (err instanceof BackendApiError) {
      return NextResponse.json({ message: "Invalid email or password." }, { status: 401 });
    }
    return NextResponse.json({ message: "Something went wrong. Please try again." }, { status: 502 });
  }
}
