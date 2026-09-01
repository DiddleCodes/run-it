import { NextRequest, NextResponse } from "next/server";
import { BackendApiError, backendFetch } from "@/lib/api/backend-client";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null);
  const token = typeof body?.token === "string" ? body.token : null;
  const newPassword = typeof body?.newPassword === "string" ? body.newPassword : null;

  if (!token || !newPassword) {
    return NextResponse.json({ message: "Token and new password are required." }, { status: 400 });
  }

  try {
    const result = await backendFetch<{ message: string }>("/auth/reset-password", {
      method: "POST",
      body: { token, newPassword },
    });
    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof BackendApiError) {
      return NextResponse.json({ message: "This reset link is invalid or has expired." }, { status: err.status });
    }
    return NextResponse.json({ message: "Something went wrong. Please try again." }, { status: 502 });
  }
}
