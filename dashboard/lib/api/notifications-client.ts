"use client";

// The signed-in account's notification feed (backend NotificationsController),
// through the same /api/proxy pass-through as everything else.

export interface DashboardNotification {
  id: string;
  type: string;
  title: string;
  body: string;
  data: { orderId?: string } | null;
  readAt: string | null;
  createdAt: string;
}

export interface NotificationFeed {
  items: DashboardNotification[];
  unreadCount: number;
}

async function call<T>(path: string, method = "GET"): Promise<T> {
  const res = await fetch(`/api/proxy/notifications${path}`, { method, headers: { "Content-Type": "application/json" } });
  if (!res.ok) throw new Error(`Notifications request failed (${res.status})`);
  return (await res.json()) as T;
}

export const notificationsClient = {
  list: () => call<NotificationFeed>("?limit=20"),
  markRead: (id: string) => call<unknown>(`/${encodeURIComponent(id)}/read`, "POST"),
  markAllRead: () => call<{ updated: number }>("/read-all", "POST"),
};
