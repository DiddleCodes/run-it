"use client";

import { ReactNode, useEffect, useState } from "react";
import { Sidebar } from "./sidebar";
import { TopBar } from "./top-bar";

interface AppShellProps {
  role: "restaurant" | "admin";
  user: { name: string | null; email: string | null; accountType: string };
  children: ReactNode;
}

export function AppShell({ role, user, children }: AppShellProps) {
  const [collapsed, setCollapsed] = useState(false);
  // Phones: the sidebar is a slide-in menu, opened from the top bar.
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  useEffect(() => {
    if (!mobileNavOpen) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && setMobileNavOpen(false);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mobileNavOpen]);

  return (
    <div className="flex h-dvh bg-[var(--background)]">
      <div className="hidden md:flex">
        <Sidebar role={role} collapsed={collapsed} onToggle={() => setCollapsed((c) => !c)} />
      </div>

      {mobileNavOpen && (
        <div className="fixed inset-0 z-50 flex md:hidden" role="dialog" aria-modal="true" aria-label="Menu">
          <Sidebar role={role} collapsed={false} mobile onToggle={() => setMobileNavOpen(false)} onNavigate={() => setMobileNavOpen(false)} />
          <button aria-label="Close menu" className="flex-1 bg-black/40" onClick={() => setMobileNavOpen(false)} />
        </div>
      )}

      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <TopBar user={user} onMenuClick={() => setMobileNavOpen(true)} />
        <main className="flex-1 overflow-y-auto p-4 sm:p-6">
          <div className="page-enter max-w-[1400px] mx-auto">{children}</div>
        </main>
      </div>
    </div>
  );
}
