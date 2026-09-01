"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

interface TopBarProps {
  user: { name: string | null; email: string | null; accountType: string };
}

const demoNotifications = [
  { text: "Order #A-1042 has been waiting 12 min", time: "2m ago", dot: "bg-amber-400" },
  { text: "New vendor application from Spice Garden", time: "18m ago", dot: "bg-blue-400" },
  { text: "Reconciliation flagged 2 stuck escrows", time: "1h ago", dot: "bg-[#7A1636]" },
];

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
      <div className="relative flex-1 max-w-xs">
        <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="absolute left-3 top-1/2 -translate-y-1/2 text-[var(--muted-foreground)]">
          <circle cx="6" cy="6" r="4.5" stroke="currentColor" strokeWidth="1.5" />
          <path d="M9.5 9.5l3 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
        <input
          type="text"
          placeholder="Search…"
          className="w-full pl-8 pr-3 py-1.5 text-sm bg-black/5 rounded-lg border border-transparent focus:border-[var(--primary)] focus:bg-white outline-none transition-all placeholder:text-[var(--muted-foreground)]"
        />
      </div>

      <div className="ml-auto flex items-center gap-1">
        <div className="relative">
          <button
            onClick={() => {
              setNotifOpen((p) => !p);
              setMenuOpen(false);
            }}
            className="relative p-2 rounded-lg text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-black/5 transition-colors"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M9 2a5 5 0 00-5 5v3l-1.5 2.5h13L14 10V7a5 5 0 00-5-5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              <path d="M7.5 15a1.5 1.5 0 003 0" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span className="absolute top-1.5 right-1.5 w-1.5 h-1.5 rounded-full bg-[#D99A18]" />
          </button>
          {notifOpen && (
            <div className="absolute right-0 top-10 w-72 bg-card border border-[var(--border)] rounded-xl shadow-xl z-50 overflow-hidden">
              <div className="px-4 py-3 border-b border-[var(--border)]">
                <p className="text-sm font-semibold">Notifications</p>
              </div>
              {demoNotifications.map((n, i) => (
                <div key={i} className="flex gap-3 px-4 py-3 hover:bg-[var(--secondary)] transition-colors cursor-pointer border-b border-[var(--border)] last:border-0">
                  <span className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${n.dot}`} />
                  <div>
                    <p className="text-sm text-[var(--foreground)]">{n.text}</p>
                    <p className="text-[11px] text-[var(--muted-foreground)] mt-0.5">{n.time}</p>
                  </div>
                </div>
              ))}
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
