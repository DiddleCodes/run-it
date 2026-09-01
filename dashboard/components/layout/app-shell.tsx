"use client";

import { ReactNode, useState } from "react";
import { Sidebar } from "./sidebar";
import { TopBar } from "./top-bar";

interface AppShellProps {
  role: "restaurant" | "admin";
  user: { name: string | null; email: string | null; accountType: string };
  children: ReactNode;
}

export function AppShell({ role, user, children }: AppShellProps) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div className="flex h-screen bg-[var(--background)]">
      <Sidebar role={role} collapsed={collapsed} onToggle={() => setCollapsed((c) => !c)} />
      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <TopBar user={user} />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="page-enter max-w-[1400px] mx-auto">{children}</div>
        </main>
      </div>
    </div>
  );
}
