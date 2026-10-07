import { act, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NotificationBell, notificationHref } from "@/components/layout/notification-bell";
import type { DashboardNotification } from "@/lib/api/notifications-client";

const push = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push }) }));

const items: DashboardNotification[] = [
  {
    id: "n2",
    type: "payout_sent",
    title: "Payout sent",
    body: "₦1,228.25 for order #24513906 is on its way to your bank account.",
    data: { orderId: "order-1790884524513906" },
    readAt: null,
    createdAt: "2026-10-07T10:00:00.000Z",
  },
  {
    id: "n1",
    type: "order_placed",
    title: "New order received",
    body: "Order #24513906 is waiting for you to accept it.",
    data: { orderId: "order-1790884524513906" },
    readAt: null,
    createdAt: "2026-10-07T09:00:00.000Z",
  },
  {
    id: "n0",
    type: "order_cancelled",
    title: "Order cancelled",
    body: "Order #11112222 was cancelled and the customer refunded. No need to prepare it.",
    data: { orderId: "order-11112222" },
    readAt: "2026-10-06T09:00:00.000Z",
    createdAt: "2026-10-06T08:00:00.000Z",
  },
];

let fetchMock: ReturnType<typeof vi.fn>;

function respond(body: unknown) {
  return Promise.resolve(new Response(JSON.stringify(body), { status: 200, headers: { "Content-Type": "application/json" } }));
}

beforeEach(() => {
  push.mockReset();
  fetchMock = vi.fn((url: string, init?: RequestInit) => {
    if (init?.method === "POST") return respond({ ok: true });
    return respond({ items, unreadCount: 2 });
  });
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => vi.unstubAllGlobals());

async function renderBell(accountType = "restaurant") {
  render(<NotificationBell accountType={accountType} />);
  await screen.findByTestId("bell-badge");
}

describe("Dashboard notification bell", () => {
  it("shows the real unread count from the backend", async () => {
    await renderBell();
    expect(screen.getByTestId("bell-badge").textContent).toBe("2");
    expect(screen.getByLabelText("Notifications, 2 unread")).toBeInTheDocument();
    expect(fetchMock).toHaveBeenCalledWith("/api/proxy/notifications?limit=20", expect.objectContaining({ method: "GET" }));
  });

  it("lists real items newest first, unread ones marked", async () => {
    await renderBell();
    fireEvent.click(screen.getByLabelText("Notifications, 2 unread"));
    const rows = await screen.findAllByRole("button", { name: /Payout sent|New order received|Order cancelled/ });
    expect(rows.map((r) => r.getAttribute("data-unread"))).toEqual(["true", "true", "false"]);
    expect(screen.getByText("₦1,228.25 for order #24513906 is on its way to your bank account.")).toBeInTheDocument();
  });

  it("opening an unread one marks it read (count drops) and goes to that order", async () => {
    await renderBell();
    fireEvent.click(screen.getByLabelText("Notifications, 2 unread"));
    fireEvent.click(await screen.findByText("New order received"));

    expect(fetchMock).toHaveBeenCalledWith("/api/proxy/notifications/n1/read", expect.objectContaining({ method: "POST" }));
    expect(push).toHaveBeenCalledWith("/restaurant/orders?order=order-1790884524513906");
    await waitFor(() => expect(screen.getByTestId("bell-badge").textContent).toBe("1"));
  });

  it("opening an already-read one does not call the backend", async () => {
    await renderBell();
    fireEvent.click(screen.getByLabelText("Notifications, 2 unread"));
    fireEvent.click(await screen.findByText("Order cancelled"));

    expect(fetchMock).not.toHaveBeenCalledWith(expect.stringContaining("/read"), expect.anything());
  });

  it('"Mark all read" clears the badge', async () => {
    await renderBell();
    fireEvent.click(screen.getByLabelText("Notifications, 2 unread"));
    await act(async () => fireEvent.click(await screen.findByText("Mark all read")));

    expect(fetchMock).toHaveBeenCalledWith("/api/proxy/notifications/read-all", expect.objectContaining({ method: "POST" }));
    expect(screen.queryByTestId("bell-badge")).toBeNull();
    expect(screen.getByLabelText("Notifications")).toBeInTheDocument();
  });

  it("an admin with nothing yet sees an honest empty state, no badge", async () => {
    fetchMock.mockImplementation(() => respond({ items: [], unreadCount: 0 }));
    render(<NotificationBell accountType="admin" />);
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    fireEvent.click(screen.getByLabelText("Notifications"));
    expect(await screen.findByText("No notifications yet")).toBeInTheDocument();
    expect(screen.queryByTestId("bell-badge")).toBeNull();
  });
});

describe("notificationHref", () => {
  it("sends a restaurant to the order, or to Profile for a failed payout", () => {
    expect(notificationHref(items[1], "restaurant")).toBe("/restaurant/orders?order=order-1790884524513906");
    expect(notificationHref({ ...items[0], type: "payout_failed" }, "restaurant")).toBe("/restaurant/profile");
    expect(notificationHref(items[0], "restaurant")).toBeNull();
    expect(notificationHref(items[1], "admin")).toBeNull();
  });
});
