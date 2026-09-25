import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { OrdersBoard } from "@/components/vendor/orders-board";
import type { IncomingOrder, IncomingOrdersResponse } from "@/lib/api/vendor-client";

vi.mock("sonner", () => ({ toast: { success: vi.fn(), error: vi.fn(), message: vi.fn() } }));

// Real-shaped payload — matches the exact response shape GET
// /vendors/me/orders/incoming returns (VendorsService.listIncomingOrders'
// explicit Prisma `select`), not a hand-waved stub.
const placedOrder: IncomingOrder = {
  id: "order-1",
  status: "placed",
  pickupCode: "XK-7291",
  totalAmount: 75000,
  deliveryLocationLabel: "Hall 4, Room 212",
  note: "Extra spicy please!",
  createdAt: "2026-08-30T14:14:00.000Z",
  items: [
    { id: "item-1", nameSnapshot: "Jollof Rice Bowl", quantity: 2, priceSnapshot: 30000 },
    { id: "item-2", nameSnapshot: "Fried Plantains", quantity: 1, priceSnapshot: 15000 },
  ],
  escrow: { foodSubtotal: 75000, restaurantCommission: 11250, restaurantPlatformFee: 20000, restaurantShare: 43750 },
};

const initialData: IncomingOrdersResponse = { items: [placedOrder], total: 1, page: 1, limit: 20 };

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe("Orders status action", () => {
  it("shows the order note inline on the row (not buried in a drawer)", () => {
    render(<OrdersBoard initialData={initialData} />);
    expect(screen.getByText(/Extra spicy please!/)).toBeInTheDocument();
  });

  it("advancing a placed order calls PATCH with {status: 'preparing'} and only updates the row after the response resolves", async () => {
    const user = userEvent.setup();
    const patchDeferred = deferred<Response>();
    const refreshDeferred = deferred<Response>();

    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      if (opts?.method === "PATCH") {
        expect(url).toBe("/api/proxy/vendors/me/orders/order-1/status");
        expect(JSON.parse(opts.body as string)).toEqual({ status: "preparing" });
        return patchDeferred.promise;
      }
      // The re-fetch after a successful action.
      return refreshDeferred.promise;
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<OrdersBoard initialData={initialData} />);
    const row = () => within(screen.getByText("XK-7291").closest("tr")!);

    expect(row().getByText("New")).toBeInTheDocument();
    expect(row().queryByText("Preparing")).not.toBeInTheDocument();

    await user.click(screen.getByRole("button", { name: "Start Preparing" }));

    // No optimistic update: still "New" while the PATCH is in flight.
    expect(row().getByText("New")).toBeInTheDocument();

    patchDeferred.resolve(new Response(JSON.stringify({}), { status: 200, headers: { "content-type": "application/json" } }));
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));

    // Still "New" — the row only updates once the follow-up GET (refresh) resolves too.
    expect(row().getByText("New")).toBeInTheDocument();

    const preparingOrder: IncomingOrder = { ...placedOrder, status: "preparing" };
    refreshDeferred.resolve(
      new Response(JSON.stringify({ items: [preparingOrder], total: 1, page: 1, limit: 20 }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );

    await waitFor(() => expect(row().getByText("Preparing")).toBeInTheDocument());
    expect(row().queryByText("New")).not.toBeInTheDocument();
  });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

describe("Task 61: declining an order", () => {
  it("only offers Decline on a placed (not yet accepted) order", () => {
    const preparing: IncomingOrder = { ...placedOrder, id: "order-2", pickupCode: "PQ-1111", status: "preparing" };
    render(<OrdersBoard initialData={{ ...initialData, items: [placedOrder, preparing], total: 2 }} />);

    const placedRow = within(screen.getByText("XK-7291").closest("tr")!);
    const preparingRow = within(screen.getByText("PQ-1111").closest("tr")!);
    expect(placedRow.getByRole("button", { name: "Decline" })).toBeInTheDocument();
    expect(preparingRow.queryByRole("button", { name: "Decline" })).not.toBeInTheDocument();
  });

  it("requires a reason, POSTs it, and only drops the order once the refresh confirms it", async () => {
    const user = userEvent.setup();
    const calls: { url: string; opts?: RequestInit }[] = [];
    const fetchMock = vi.fn((url: string, opts?: RequestInit) => {
      calls.push({ url, opts });
      if (opts?.method === "POST") return Promise.resolve(json({ id: "order-1", status: "cancelled" }));
      return Promise.resolve(json({ items: [], total: 0, page: 1, limit: 20 }));
    });
    vi.stubGlobal("fetch", fetchMock);

    render(<OrdersBoard initialData={initialData} />);
    await user.click(screen.getByRole("button", { name: "Decline" }));

    const confirm = () => screen.getByRole("button", { name: "Decline order" });
    expect(confirm()).toBeDisabled();

    await user.click(screen.getByLabelText("Out of stock"));
    expect(confirm()).toBeEnabled();
    await user.click(confirm());

    await waitFor(() => expect(screen.queryByText("XK-7291")).not.toBeInTheDocument());
    const post = calls.find((c) => c.opts?.method === "POST")!;
    expect(post.url).toBe("/api/proxy/vendors/me/orders/order-1/decline");
    expect(JSON.parse(post.opts!.body as string)).toEqual({ reason: "out_of_stock" });
  });

  it("'Other' stays disabled until real free text is typed, and sends it trimmed", async () => {
    const user = userEvent.setup();
    const fetchMock = vi.fn((_url: string, opts?: RequestInit) =>
      Promise.resolve(opts?.method === "POST" ? json({}) : json({ items: [], total: 0, page: 1, limit: 20 })),
    );
    vi.stubGlobal("fetch", fetchMock);

    render(<OrdersBoard initialData={initialData} />);
    await user.click(screen.getByRole("button", { name: "Decline" }));
    await user.click(screen.getByLabelText("Other"));

    const confirm = screen.getByRole("button", { name: "Decline order" });
    expect(confirm).toBeDisabled();
    await user.type(screen.getByLabelText("Reason (shown to the student)"), "   ");
    expect(confirm).toBeDisabled();
    await user.type(screen.getByLabelText("Reason (shown to the student)"), "Gas ran out ");
    expect(confirm).toBeEnabled();
    await user.click(confirm);

    await waitFor(() => expect(fetchMock.mock.calls.some(([, o]) => o?.method === "POST")).toBe(true));
    const [, opts] = fetchMock.mock.calls.find(([, o]) => o?.method === "POST")!;
    expect(JSON.parse(opts!.body as string)).toEqual({ reason: "other", note: "Gas ran out" });
  });

  it("shows the backend's real rejection and keeps the order when declining fails", async () => {
    const user = userEvent.setup();
    const { toast } = await import("sonner");
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve(json({ message: 'Cannot decline order order-1 — it is currently "preparing", not "placed"', statusCode: 409 }, 409)),
      ),
    );

    render(<OrdersBoard initialData={initialData} />);
    await user.click(screen.getByRole("button", { name: "Decline" }));
    await user.click(screen.getByLabelText("Too busy"));
    await user.click(screen.getByRole("button", { name: "Decline order" }));

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith(expect.stringContaining("currently \"preparing\""), expect.anything()),
    );
    expect(screen.getByText("XK-7291")).toBeInTheDocument();
  });
});

