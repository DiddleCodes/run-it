"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

interface TopBarProps {
  user: { name: string | null; email: string | null; accountType: string };
}

export function TopBar({ user }: TopBarProps) {
  const router = useRouter();
  const [menuOpen, setMenuOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);

  const displayName = user.name ?? user.email ?? "Account";
  const initials = displayName
    .split(" ")
    .map((n) => n[0])
    .filter(Boolean)
    .slice(0, 2)
    .join("")
    .toUpperCase();

  async function handleLogout() {
    await fetch("/api/auth/logout", { method: "POST" });
    router.push("/login");
    router.refresh();
  }

  return (
    <header className="glass-bar h-14 flex items-center px-5 border-b border-black/5 flex-shrink-0 gap-4 sticky top-0 z-30">
      <div className="ml-auto flex items-center gap-1">
        <div className="relative">
          <button
            onClick={() => {
              setNotifOpen((p) => !p);
              setMenuOpen(false);
            }}
            aria-label="Notifications"
            className="relative p-2 rounded-lg text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-black/5 transition-colors"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M9 2a5 5 0 00-5 5v3l-1.5 2.5h13L14 10V7a5 5 0 00-5-5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              <path d="M7.5 15a1.5 1.5 0 003 0" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          </button>
          {notifOpen && (
            <div className="absolute right-0 top-10 w-72 bg-card border border-[var(--border)] rounded-xl shadow-xl z-50 overflow-hidden">
              <div className="px-4 py-3 border-b border-[var(--border)]">
                <p className="text-sm font-semibold">Notifications</p>
              </div>
              {/* No notification feed exists yet — say so rather than show made-up alerts. */}
              <div className="px-4 py-6 text-center">
                <p className="text-sm text-[var(--foreground)]">No notifications yet</p>
                <p className="text-[11px] text-[var(--muted-foreground)] mt-1">Order and dispute alerts are coming soon.</p>
              </div>
            </div>
          )}
        </div>

        <div className="relative">
          <button
            onClick={() => {
              setMenuOpen((p) => !p);
              setNotifOpen(false);
            }}
            className="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-black/5 transition-colors"
          >
            <div className="w-7 h-7 rounded-full bg-gradient-to-br from-[#7A1636] to-[#D99A18] flex items-center justify-center text-white text-xs font-semibold flex-shrink-0">
              {initials || "?"}
            </div>
            <div className="text-left hidden sm:block">
              <p className="text-xs font-medium text-[var(--foreground)] leading-tight">{displayName}</p>
              <p className="text-[10px] text-[var(--muted-foreground)] capitalize">{user.accountType}</p>
            </div>
            <svg width="12" height="12" viewBox="0 0 12 12" fill="none" className="text-[var(--muted-foreground)] ml-1">
              <path d="M3 4.5l3 3 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>

          {menuOpen && (
            <div className="absolute right-0 top-10 w-44 bg-card border border-[var(--border)] rounded-xl shadow-xl z-50 overflow-hidden">
              <div className="px-4 py-3 border-b border-[var(--border)]">
                <p className="text-xs font-medium text-[var(--foreground)]">{displayName}</p>
                <p className="text-[11px] text-[var(--muted-foreground)]">{user.email}</p>
              </div>
              <button onClick={handleLogout} className="w-full flex items-center gap-2 px-4 py-2.5 text-sm text-red-500 hover:bg-red-50 transition-colors">
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M5 2H3a1 1 0 00-1 1v8a1 1 0 001 1h2M10 10l3-3-3-3M13 7H6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
                Sign out
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
