"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { notificationsClient, type DashboardNotification, type NotificationFeed } from "@/lib/api/notifications-client";
import { formatDateTime } from "@/lib/format";

const POLL_MS = 30_000;

/** Where clicking a notification goes — null just marks it read. */
export function notificationHref(n: DashboardNotification, accountType: string): string | null {
  if (accountType !== "restaurant") return null;
  const orderId = n.data?.orderId;
  const code = n.data?.pickupCode;
  switch (n.type) {
    case "order_placed":
    case "order_cancelled":
    case "dispute_opened":
      if (!orderId) return "/restaurant/orders";
      return `/restaurant/orders?order=${encodeURIComponent(orderId)}${code ? `&code=${encodeURIComponent(code)}` : ""}`;
    case "payout_failed":
      return "/restaurant/profile";
    default:
      return null;
  }
}

export function NotificationBell({
  accountType,
  open: controlledOpen,
  onOpenChange,
}: {
  accountType: string;
  /** Optional: the top bar controls it so the bell and account menu close each other. */
  open?: boolean;
  onOpenChange?: (open: boolean) => void;
}) {
  const router = useRouter();
  const [ownOpen, setOwnOpen] = useState(false);
  const open = controlledOpen ?? ownOpen;
  const setOpen = (next: boolean) => {
    setOwnOpen(next);
    onOpenChange?.(next);
  };
  const [feed, setFeed] = useState<NotificationFeed | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(
    () =>
      notificationsClient.list().then(
        (next) => {
          setFeed(next);
          setFailed(false);
        },
        () => setFailed(true),
      ),
    [],
  );

  // On mount, every 30s, and whenever the tab regains focus.
  useEffect(() => {
    load();
    const timer = setInterval(load, POLL_MS);
    window.addEventListener("focus", load);
    return () => {
      clearInterval(timer);
      window.removeEventListener("focus", load);
    };
  }, [load]);

  function toggle() {
    const next = !open;
    setOpen(next);
    if (next) load();
  }

  // Shown as read straight away; the next load reflects what the backend has.
  function markLocally(ids: string[] | "all") {
    setFeed((f) => {
      if (!f) return f;
      const now = new Date().toISOString();
      const hit = (n: DashboardNotification) => ids === "all" || ids.includes(n.id);
      const newlyRead = f.items.filter((n) => hit(n) && !n.readAt).length;
      return {
        items: f.items.map((n) => (hit(n) && !n.readAt ? { ...n, readAt: now } : n)),
        unreadCount: ids === "all" ? 0 : Math.max(0, f.unreadCount - newlyRead),
      };
    });
  }

  async function openItem(n: DashboardNotification) {
    if (!n.readAt) {
      markLocally([n.id]);
      notificationsClient.markRead(n.id).catch(load);
    }
    const href = notificationHref(n, accountType);
    if (href) {
      setOpen(false);
      router.push(href);
    }
  }

  async function markAll() {
    markLocally("all");
    notificationsClient.markAllRead().catch(load);
  }

  const unread = feed?.unreadCount ?? 0;

  return (
    <div className="relative">
      <button
        onClick={toggle}
        aria-label={unread > 0 ? `Notifications, ${unread} unread` : "Notifications"}
        className="relative p-2 rounded-lg text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-black/5 transition-colors"
      >
        <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
          <path d="M9 2a5 5 0 00-5 5v3l-1.5 2.5h13L14 10V7a5 5 0 00-5-5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
          <path d="M7.5 15a1.5 1.5 0 003 0" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
        {unread > 0 && (
          <span
            data-testid="bell-badge"
            className="absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 rounded-full bg-[var(--primary)] text-white text-[10px] font-semibold leading-[18px] text-center"
          >
            {unread > 9 ? "9+" : unread}
          </span>
        )}
      </button>
      {open && (
        <div className="absolute right-0 top-10 w-80 bg-card border border-[var(--border)] rounded-xl shadow-xl z-50 overflow-hidden">
          <div className="px-4 py-3 border-b border-[var(--border)] flex items-center justify-between">
            <p className="text-sm font-semibold">Notifications</p>
            {unread > 0 && (
              <button onClick={markAll} className="text-xs font-medium text-[var(--primary)] hover:underline">
                Mark all read
              </button>
            )}
          </div>
          <div className="max-h-96 overflow-y-auto">
            {feed && feed.items.length > 0 ? (
              feed.items.map((n) => (
                <button
                  key={n.id}
                  onClick={() => openItem(n)}
                  data-unread={!n.readAt}
                  className={`w-full text-left flex gap-3 px-4 py-3 border-b border-[var(--border)] last:border-0 hover:bg-[var(--secondary)] transition-colors ${n.readAt ? "opacity-70" : ""}`}
                >
                  <span className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${n.readAt ? "bg-transparent" : "bg-[var(--primary)]"}`} />
                  <span className="min-w-0">
                    <span className={`block text-sm text-[var(--foreground)] ${n.readAt ? "" : "font-semibold"}`}>{n.title}</span>
                    <span className="block text-xs text-[var(--muted-foreground)] mt-0.5">{n.body}</span>
                    <span className="block text-[11px] text-[var(--muted-foreground)] mt-1">{formatDateTime(n.createdAt)}</span>
                  </span>
                </button>
              ))
            ) : (
              <div className="px-4 py-6 text-center">
                <p className="text-sm text-[var(--foreground)]">{failed && !feed ? "Couldn't load notifications" : "No notifications yet"}</p>
                <p className="text-[11px] text-[var(--muted-foreground)] mt-1">
                  {failed && !feed ? "We'll try again shortly." : accountType === "restaurant" ? "New orders, cancellations, disputes and payouts show up here." : "Alerts for your account show up here."}
                </p>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
