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
  createdAt: "2026-08-30T14:14:00.000Z",
  items: [
    { id: "item-1", nameSnapshot: "Jollof Rice Bowl", quantity: 2, priceSnapshot: 30000, notes: "Extra spicy please!" },
    { id: "item-2", nameSnapshot: "Fried Plantains", quantity: 1, priceSnapshot: 15000, notes: null },
  ],
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
  it("shows the item note inline on the row (not buried in a drawer)", () => {
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
