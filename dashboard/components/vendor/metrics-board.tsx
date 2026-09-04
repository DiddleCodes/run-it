"use client";

import { useState } from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Column, DataTable } from "@/components/shared/data-table";
import { StatCard } from "@/components/shared/stat-card";
import { SkeletonBlock } from "@/components/shared/skeleton-block";
import { formatKobo } from "@/lib/format";
import { Metrics, MetricsItem, vendorClient } from "@/lib/api/vendor-client";

const RANGES = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];

interface TooltipPayloadEntry {
  color?: string;
  name?: string;
  value?: number;
}

function ChartTooltip({ active, payload, label }: { active?: boolean; payload?: TooltipPayloadEntry[]; label?: string }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-[var(--border)] rounded-lg px-3 py-2 shadow-lg text-xs max-w-[220px]">
      <p className="font-medium mb-1 truncate">{label}</p>
      {payload.map((p, i) => (
        <p key={i} style={{ color: p.color }}>
          {p.name === "revenue" ? formatKobo(p.value ?? 0) : p.value}
        </p>
      ))}
    </div>
  );
}

export function MetricsBoard({ initialData }: { initialData: Metrics }) {
  const [metrics, setMetrics] = useState<Metrics>(initialData);
  const [rangeDays, setRangeDays] = useState(30);
  const [loading, setLoading] = useState(false);

  async function selectRange(days: number) {
    setRangeDays(days);
    setLoading(true);
    try {
      const to = new Date();
      const from = new Date(to.getTime() - days * 24 * 60 * 60 * 1000);
      const data = await vendorClient.getMetrics({ from: from.toISOString(), to: to.toISOString() });
      setMetrics(data);
    } finally {
      setLoading(false);
    }
  }

  const avgOrderValue = metrics.totalOrders > 0 ? Math.round(metrics.totalRevenue / metrics.totalOrders) : 0;
  const byCount = [...metrics.mostOrderedItems].sort((a, b) => b.count - a.count).slice(0, 8);
  const byRevenue = [...metrics.mostOrderedItems].sort((a, b) => b.revenue - a.revenue);
  const revenueTotal = byRevenue.reduce((sum, i) => sum + i.revenue, 0);
  // DataTable requires an `id` field; menuItemId can be null for an
  // unlinked/since-deleted item, same fallback key the old row used.
  const revenueRows = byRevenue.map((item) => ({ ...item, id: item.menuItemId ?? item.name }));

  const revenueColumns: Column<MetricsItem & { id: string }>[] = [
    {
      key: "name",
      header: "Item",
      render: (item) => {
        const rank = revenueRows.findIndex((r) => r.id === item.id) + 1;
        return (
          <div className="flex items-center gap-2">
            <span className="w-5 h-5 rounded-full bg-[var(--secondary)] flex items-center justify-center text-[10px] font-bold text-[var(--muted-foreground)]">
              {rank}
            </span>
            {item.name}
          </div>
        );
      },
    },
    { key: "count", header: "Orders", className: "text-right", render: (item) => <span>{item.count}</span> },
    {
      key: "revenue",
      header: "Revenue",
      className: "text-right",
      render: (item) => <span className="font-medium text-[var(--primary)]">{formatKobo(item.revenue)}</span>,
    },
    {
      key: "pct",
      header: "% of total",
      className: "text-right",
      render: (item) => {
        const pct = revenueTotal > 0 ? ((item.revenue / revenueTotal) * 100).toFixed(1) : "0.0";
        return (
          <div className="flex items-center justify-end gap-2">
            <div className="w-16 h-1.5 bg-[var(--muted)] rounded-full overflow-hidden">
              <div className="h-full bg-[#7A1636] rounded-full" style={{ width: `${pct}%` }} />
            </div>
            <span className="text-xs text-[var(--muted-foreground)]">{pct}%</span>
          </div>
        );
      },
    },
  ];

  return (
    <>
      <div className="flex items-center justify-end mb-6">
        <div className="flex rounded-lg border border-[var(--border)] overflow-hidden bg-card">
          {RANGES.map((r) => (
            <button
              key={r.days}
              onClick={() => selectRange(r.days)}
              className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                r.days === rangeDays ? "bg-[var(--primary)] text-white" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="9" r="7" stroke="currentColor" strokeWidth="1.5" />
              <path d="M9 5v4l2.5 2.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          }
          label="Total revenue"
          value={loading ? "" : formatKobo(metrics.totalRevenue)}
          accent="burgundy"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M3 3h12M3 3l1.5 10H13.5L15 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          }
          label="Total orders"
          value={loading ? "" : metrics.totalOrders}
          accent="gold"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M2 14L6 9l3 3 3-4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          }
          label="Avg. order value"
          value={loading ? "" : formatKobo(avgOrderValue)}
          accent="green"
          loading={loading}
        />
      </div>

      <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] p-5 mb-6">
        <h3 className="font-semibold text-[var(--foreground)] mb-4">Most ordered items</h3>
        {loading ? (
          <SkeletonBlock className="h-[220px]" />
        ) : byCount.length === 0 ? (
          <p className="text-sm text-[var(--muted-foreground)] py-10 text-center">No orders in this date range yet.</p>
        ) : (
          <ResponsiveContainer width="100%" height={Math.max(220, byCount.length * 34)}>
            <BarChart data={byCount} layout="vertical" margin={{ left: 10, right: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" horizontal={false} />
              <XAxis type="number" tick={{ fontSize: 10, fill: "var(--muted-foreground)" }} allowDecimals={false} />
              <YAxis type="category" dataKey="name" width={140} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} />
              <Tooltip content={<ChartTooltip />} />
              <Bar dataKey="count" name="orders" fill="#7A1636" radius={[0, 3, 3, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      <h3 className="font-semibold text-[var(--foreground)] mb-3">Revenue per item</h3>
      <DataTable
        columns={revenueColumns}
        data={revenueRows}
        loading={loading}
        emptyTitle="No revenue yet"
        emptyDescription="No orders in this date range yet."
      />
    </>
  );
}
