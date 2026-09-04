import { ReactNode } from "react";
import { redirect } from "next/navigation";
import { AppShell } from "@/components/layout/app-shell";
import { getCurrentUser } from "@/lib/auth/current-user";
import { getSession } from "@/lib/auth/session";

// Defense in depth: proxy.ts (Next.js 16's renamed middleware.ts
// convention) already blocks a non-admin account from reaching here, but
// this layout re-checks independently rather than trusting that the
// cookie's mere presence means the caller is an admin.
export default async function AdminLayout({ children }: { children: ReactNode }) {
  const session = await getSession();
  if (!session || session.role !== "admin") {
    redirect(session?.accountType === "restaurant" ? "/restaurant/overview" : "/login");
  }

  const user = await getCurrentUser();
  if (!user) redirect("/login");

  return (
    <AppShell role="admin" user={user}>
      {children}
    </AppShell>
  );
}
