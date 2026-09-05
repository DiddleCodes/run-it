"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { Drawer } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime, formatKobo } from "@/lib/format";
import { usePolling } from "@/lib/hooks/use-polling";
import { toast } from "@/lib/toast";
import { IncomingOrder, IncomingOrdersResponse, OrderStatus, VendorApiError, vendorClient } from "@/lib/api/vendor-client";

const NEXT_ACTION: Partial<Record<OrderStatus, { label: string; next: "preparing" | "ready_for_pickup" }>> = {
  placed: { label: "Start Preparing", next: "preparing" },
  preparing: { label: "Mark Ready for Pickup", next: "ready_for_pickup" },
};

const TABS: { key: OrderStatus | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "placed", label: "New" },
  { key: "preparing", label: "Preparing" },
  { key: "ready_for_pickup", label: "Ready for Pickup" },
  { key: "picked_up", label: "Out for Delivery" },
];

function itemsSummary(order: IncomingOrder): string {
  return order.items.map((i) => `${i.quantity}× ${i.nameSnapshot}`).join(", ");
}

export function OrdersBoard({ initialData }: { initialData: IncomingOrdersResponse }) {
  const [orders, setOrders] = useState<IncomingOrder[]>(initialData.items);
  const [filter, setFilter] = useState<OrderStatus | "all">("all");
  const [selected, setSelected] = useState<IncomingOrder | null>(null);
  const [actioningId, setActioningId] = useState<string | null>(null);

  async function refresh() {
    try {
      const res = await vendorClient.getIncomingOrders();
      setOrders(res.items);
      // Keep the drawer's own copy in sync if it's open on an order still present.
      setSelected((prev) => (prev ? (res.items.find((o) => o.id === prev.id) ?? null) : null));
    } catch {
      // Silent — a failed background poll shouldn't interrupt the vendor; the next tick retries.
    }
  }

  usePolling(refresh, 10_000);

  async function advance(order: IncomingOrder) {
    const action = NEXT_ACTION[order.status];
    if (!action) return;
    setActioningId(order.id);
    try {
      await vendorClient.updateOrderStatus(order.id, action.next);
      await refresh();
      toast.success(`Order updated to "${action.next === "preparing" ? "Preparing" : "Ready for pickup"}"`);
    } catch (err) {
      toast.error(err instanceof VendorApiError ? err.message : "Couldn't update the order. Please try again.");
    } finally {
      setActioningId(null);
    }
  }

  const filtered = filter === "all" ? orders : orders.filter((o) => o.status === filter);

  const columns: Column<IncomingOrder>[] = [
    {
      key: "pickupCode",
      header: "Order",
      render: (o) => <span className="font-mono text-xs font-semibold text-[var(--foreground)]">{o.pickupCode}</span>,
    },
    {
      key: "items",
      header: "Items",
      render: (o) => <span className="text-sm">{itemsSummary(o)}</span>,
    },
    {
      key: "notes",
      header: "Notes",
      render: (o) => {
        if (!o.note) return <span className="text-xs text-[var(--muted-foreground)]">—</span>;
        return (
          <span className="text-xs px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 border border-amber-200 font-medium">
            {o.note}
          </span>
        );
      },
    },
    { key: "status", header: "Status", render: (o) => <StatusBadge status={o.status} /> },
    { key: "totalAmount", header: "Total", sortable: true, render: (o) => formatKobo(o.totalAmount) },
    { key: "createdAt", header: "Placed", sortable: true, render: (o) => formatDateTime(o.createdAt) },
    {
      key: "action",
      header: "",
      render: (o) => {
        const action = NEXT_ACTION[o.status];
        if (!action) return null;
        return (
          <button
            onClick={(e) => {
              e.stopPropagation();
              advance(o);
            }}
            disabled={actioningId === o.id}
            className="px-3 py-1.5 rounded-lg bg-[var(--primary)] text-white text-xs font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {actioningId === o.id ? "Updating…" : action.label}
          </button>
        );
      },
    },
  ];

  return (
    <>
      <div className="flex gap-1 mb-4 flex-wrap">
        {TABS.map((t) => {
          const count = t.key === "all" ? orders.length : orders.filter((o) => o.status === t.key).length;
          return (
            <button
              key={t.key}
              onClick={() => setFilter(t.key)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                filter === t.key ? "bg-[var(--primary)] text-white" : "bg-card border border-[var(--border)] text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {t.label}
              <span className={`ml-1.5 px-1.5 py-0.5 rounded-full text-[10px] font-semibold ${filter === t.key ? "bg-white/20 text-white" : "bg-[var(--secondary)]"}`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        emptyTitle="No orders here"
        emptyDescription="New orders will appear automatically — this list refreshes every 10 seconds."
        onRowClick={setSelected}
      />

      <Drawer open={!!selected} onOpenChange={(open) => !open && setSelected(null)} title={selected ? `Order ${selected.pickupCode}` : ""}>
        {selected && (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <StatusBadge status={selected.status} />
              <span className="text-sm text-[var(--muted-foreground)]">{formatDateTime(selected.createdAt)}</span>
            </div>

            {selected.deliveryLocationLabel && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Delivery location</p>
                <p className="text-sm text-[var(--foreground)]">{selected.deliveryLocationLabel}</p>
              </div>
            )}

            {selected.note && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Note</p>
                <p className="text-sm text-amber-700 bg-amber-50 border border-amber-200 rounded px-2 py-1.5">{selected.note}</p>
              </div>
            )}

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Items</p>
              <div className="space-y-2">
                {selected.items.map((item) => (
                  <div key={item.id} className="py-2 border-b border-[var(--border)] last:border-0">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-[var(--foreground)]">
                        {item.nameSnapshot} ×{item.quantity}
                      </span>
                      <span className="text-sm font-medium">{formatKobo(item.priceSnapshot * item.quantity)}</span>
                    </div>
                  </div>
                ))}
                <div className="flex items-center justify-between pt-1">
                  <span className="text-sm font-semibold">Total</span>
                  <span className="text-base font-bold text-[var(--primary)]">{formatKobo(selected.totalAmount)}</span>
                </div>
              </div>
            </div>

            {selected.escrow && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Your payout</p>
                <div className="rounded-xl border border-[var(--border)] divide-y divide-[var(--border)] text-sm">
                  <div className="flex items-center justify-between px-3 py-2">
                    <span className="text-[var(--muted-foreground)]">Food subtotal</span>
                    <span className="text-[var(--foreground)]">{formatKobo(selected.escrow.foodSubtotal)}</span>
                  </div>
                  <div className="flex items-center justify-between px-3 py-2">
                    <span className="text-[var(--muted-foreground)]">Commission (15%)</span>
                    <span className="text-[var(--foreground)]">−{formatKobo(selected.escrow.restaurantCommission)}</span>
                  </div>
                  <div className="flex items-center justify-between px-3 py-2">
                    <span className="text-[var(--muted-foreground)]">Platform Service Fee</span>
                    <span className="text-[var(--foreground)]">−{formatKobo(selected.escrow.restaurantPlatformFee)}</span>
                  </div>
                  <div className="flex items-center justify-between px-3 py-2 bg-[var(--secondary)] rounded-b-xl">
                    <span className="font-semibold text-[var(--foreground)]">Net payout</span>
                    <span className="font-bold text-[var(--primary)]">{formatKobo(selected.escrow.restaurantShare)}</span>
                  </div>
                </div>
              </div>
            )}

            {(selected.status === "ready_for_pickup" || selected.status === "picked_up") && (
              <div className="p-4 rounded-xl bg-[var(--secondary)] text-center">
                <p className="text-xs text-[var(--muted-foreground)] mb-1">Pickup code</p>
                <p className="font-fraunces text-3xl font-semibold text-[var(--foreground)] tracking-wider">{selected.pickupCode}</p>
              </div>
            )}

            {NEXT_ACTION[selected.status] && (
              <button
                onClick={() => advance(selected)}
                disabled={actioningId === selected.id}
                className="w-full py-2.5 rounded-lg bg-[var(--primary)] text-white font-medium transition-colors hover:bg-[#5A0E25] disabled:opacity-50"
              >
                {actioningId === selected.id ? "Updating…" : NEXT_ACTION[selected.status]!.label}
              </button>
            )}
          </div>
        )}
      </Drawer>
    </>
  );
}
