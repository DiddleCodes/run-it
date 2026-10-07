"use client";

import { useState } from "react";
import Link from "next/link";
import { Banknote, Clock, TriangleAlert } from "lucide-react";
import { Column, DataTable } from "@/components/shared/data-table";
import { StatCard } from "@/components/shared/stat-card";
import { StatusBadge } from "@/components/shared/status-badge";
import { vendorClient, type Earnings, type EarningsLine } from "@/lib/api/vendor-client";
import { formatDateTime, formatKobo } from "@/lib/format";

const RANGES = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];

const DAY_MS = 24 * 60 * 60 * 1000;

/** A yyyy-mm-dd picked in the date inputs, as the start/end of that day in Lagos. */
function lagosDayStart(date: string) {
  return new Date(`${date}T00:00:00+01:00`).toISOString();
}
function lagosDayEnd(date: string) {
  return new Date(`${date}T23:59:59.999+01:00`).toISOString();
}

export function EarningsBoard({ initialData }: { initialData: Earnings }) {
  const [earnings, setEarnings] = useState<Earnings>(initialData);
  const [rangeDays, setRangeDays] = useState<number | null>(30);
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [loading, setLoading] = useState(false);
  const [failedToLoad, setFailedToLoad] = useState(false);

  async function load(params: { from: string; to: string }) {
    setLoading(true);
    setFailedToLoad(false);
    try {
      setEarnings(await vendorClient.getEarnings(params));
    } catch {
      setFailedToLoad(true);
    } finally {
      setLoading(false);
    }
  }

  function selectPreset(days: number) {
    setRangeDays(days);
    const to = new Date();
    void load({ from: new Date(to.getTime() - days * DAY_MS).toISOString(), to: to.toISOString() });
  }

  function applyCustom() {
    if (!customFrom || !customTo || customFrom > customTo) return;
    setRangeDays(null);
    void load({ from: lagosDayStart(customFrom), to: lagosDayEnd(customTo) });
  }

  const { summary } = earnings;
  const rows = earnings.items.map((line) => ({ ...line, id: line.orderId }));

  const columns: Column<EarningsLine & { id: string }>[] = [
    {
      key: "pickupCode",
      header: "Order",
      render: (o) => <span className="font-semibold text-[var(--foreground)]">Order {o.pickupCode}</span>,
    },
    {
      key: "deliveredAt",
      header: "Delivered",
      sortable: true,
      render: (o) => (o.deliveredAt ? formatDateTime(o.deliveredAt) : "—"),
    },
    { key: "foodSubtotalKobo", header: "Food total", align: "right", render: (o) => formatKobo(o.foodSubtotalKobo) },
    {
      key: "commissionKobo",
      header: "Bridgit commission",
      align: "right",
      render: (o) => <span className="text-[var(--muted-foreground)]">−{formatKobo(o.commissionKobo)}</span>,
    },
    {
      key: "payoutKobo",
      header: "Payout",
      align: "right",
      sortable: true,
      render: (o) => <span className="font-semibold text-[var(--foreground)]">{formatKobo(o.payoutKobo)}</span>,
    },
    {
      key: "payoutStatus",
      header: "Status",
      render: (o) =>
        o.payoutStatus === "failed" ? (
          <span className="inline-flex items-center gap-2">
            <StatusBadge status="failed" size="sm" />
            <Link href="/restaurant/profile" className="text-xs font-medium text-red-600 hover:underline">
              Fix payout account
            </Link>
          </span>
        ) : (
          <StatusBadge status={o.payoutStatus} size="sm" />
        ),
    },
  ];

  return (
    <>
      <div className="flex flex-wrap items-center justify-end gap-3 mb-6">
        <div className="flex items-center gap-2 text-xs text-[var(--muted-foreground)]">
          <label className="flex items-center gap-1">
            From
            <input
              type="date"
              aria-label="From"
              value={customFrom}
              onChange={(e) => setCustomFrom(e.target.value)}
              className="rounded-md border border-[var(--border)] bg-card px-2 py-1 text-[var(--foreground)]"
            />
          </label>
          <label className="flex items-center gap-1">
            To
            <input
              type="date"
              aria-label="To"
              value={customTo}
              onChange={(e) => setCustomTo(e.target.value)}
              className="rounded-md border border-[var(--border)] bg-card px-2 py-1 text-[var(--foreground)]"
            />
          </label>
          <button
            onClick={applyCustom}
            disabled={!customFrom || !customTo || customFrom > customTo}
            className="rounded-md border border-[var(--border)] bg-card px-2.5 py-1 font-medium text-[var(--foreground)] disabled:opacity-40"
          >
            Apply
          </button>
        </div>
        <div className="flex rounded-lg border border-[var(--border)] overflow-hidden bg-card">
          {RANGES.map((r) => (
            <button
              key={r.days}
              onClick={() => selectPreset(r.days)}
              className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                r.days === rangeDays ? "bg-[var(--primary)] text-white" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
        <StatCard
          icon={<Banknote size={16} />}
          label={`Settled (${summary.settledCount} ${summary.settledCount === 1 ? "order" : "orders"}, this range)`}
          value={loading ? "" : formatKobo(summary.settledKobo)}
          accent="green"
          loading={loading}
        />
        <StatCard
          icon={<Clock size={16} />}
          label={`Pending (${summary.pendingCount} delivered, not yet paid out)`}
          value={loading ? "" : formatKobo(summary.pendingKobo)}
          accent="gold"
          loading={loading}
        />
        <StatCard
          icon={<TriangleAlert size={16} />}
          label={`Failed (${summary.failedCount} needing attention)`}
          value={loading ? "" : formatKobo(summary.failedKobo)}
          accent="burgundy"
          loading={loading}
        />
      </div>

      {summary.failedCount > 0 && !loading && (
        <div role="alert" className="mb-4 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
          <span>
            {summary.failedCount === 1 ? "1 payout" : `${summary.failedCount} payouts`} ({formatKobo(summary.failedKobo)}) couldn&apos;t be
            sent to your bank.
          </span>
          <Link href="/restaurant/profile" className="font-semibold underline">
            Check your payout account in Profile
          </Link>
        </div>
      )}

      {failedToLoad && (
        <p role="alert" className="mb-4 text-sm text-red-600">
          Couldn&apos;t load earnings for that range. Try again.
        </p>
      )}

      <DataTable
        columns={columns}
        data={rows}
        loading={loading}
        emptyTitle="No earnings in this range"
        emptyDescription="Delivered orders and their payouts will show up here."
      />
    </>
  );
}
