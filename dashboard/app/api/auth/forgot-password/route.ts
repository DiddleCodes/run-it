import { NextRequest, NextResponse } from "next/server";
import { backendFetch } from "@/lib/api/backend-client";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  const email = typeof body?.email === "string" ? body.email : null;

  if (!email) {
    return NextResponse.json({ message: "Email is required." }, { status: 400 });
  }

  // The backend already returns the same generic message whether or not the
  // email matched an account — this proxy just forwards it verbatim rather
  // than adding its own branching, so that guarantee isn't accidentally
  // undone here.
  const result = await backendFetch<{ message: string }>("/auth/forgot-password", {
    method: "POST",
    body: { email },
  });
  return NextResponse.json(result);
}
