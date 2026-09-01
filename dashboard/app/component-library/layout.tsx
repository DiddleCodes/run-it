import { ReactNode } from "react";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/layout/app-shell";
import { getCurrentUser } from "@/lib/auth/current-user";
import { getSession } from "@/lib/auth/session";

export default async function ComponentLibraryLayout({ children }: { children: ReactNode }) {
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
