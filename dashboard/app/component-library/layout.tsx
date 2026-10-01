import { ReactNode } from "react";
import { notFound, redirect } from "next/navigation";
import { AppShell } from "@/components/layout/app-shell";
import { getCurrentUser } from "@/lib/auth/current-user";
import { getSession } from "@/lib/auth/session";

export default async function ComponentLibraryLayout({ children }: { children: ReactNode }) {
  // A developer reference with made-up sample data — never part of the
  // production app, not even by direct URL.
  if (process.env.NODE_ENV === "production") notFound();

  const session = await getSession();
  if (!session) redirect("/login");

  const user = await getCurrentUser();
  if (!user) redirect("/login");

  return (
    <AppShell role={session.role === "admin" ? "admin" : "restaurant"} user={user}>
      {children}
    </AppShell>
  );
}
