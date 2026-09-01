"use client";

import { useState } from "react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { StatCard } from "@/components/shared/stat-card";
import { SkeletonBlock } from "@/components/shared/skeleton-block";
import { formatKobo } from "@/lib/format";
import { PlatformMetrics, adminClient } from "@/lib/api/admin-client";

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
          {formatKobo(p.value ?? 0)}
        </p>
      ))}
    </div>
  );
}

export function PlatformMetricsBoard({ initialData }: { initialData: PlatformMetrics }) {
  const [metrics, setMetrics] = useState<PlatformMetrics>(initialData);
  const [rangeDays, setRangeDays] = useState(30);
  const [loading, setLoading] = useState(false);

  async function selectRange(days: number) {
    setRangeDays(days);
    setLoading(true);
    try {
      const to = new Date();
      const from = new Date(to.getTime() - days * 24 * 60 * 60 * 1000);
      const data = await adminClient.getPlatformMetrics({ from: from.toISOString(), to: to.toISOString() });
      setMetrics(data);
    } finally {
      setLoading(false);
    }
  }

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

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 mb-6">
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="9" r="7" stroke="currentColor" strokeWidth="1.5" />
              <path d="M9 5v4l2.5 2.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          }
          label="GMV"
          value={loading ? "" : formatKobo(metrics.gmv)}
          accent="burgundy"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M3 3h12M3 3l1.5 10H13.5L15 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          }
          label="Order volume"
          value={loading ? "" : metrics.orderVolume}
          accent="gold"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M3 3h10v1.5a2 2 0 01-2 2H5a2 2 0 01-2-2V3z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
            </svg>
          }
          label="Active vendors"
          value={loading ? "" : metrics.activeVendors}
          accent="green"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <circle cx="9" cy="6" r="3" stroke="currentColor" strokeWidth="1.5" />
              <path d="M3 15c0-3.3 2.7-6 6-6s6 2.7 6 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          }
          label="Active runners"
          value={loading ? "" : metrics.activeRunners}
          accent="gold"
          loading={loading}
        />
        <StatCard
          icon={
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
              <path d="M2 14L6 9l3 3 3-4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          }
          label="Platform revenue"
          value={loading ? "" : `${formatKobo(metrics.platformRevenue)} (${metrics.takeRatePct.toFixed(1)}%)`}
          accent="burgundy"
          loading={loading}
        />
      </div>

      <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] p-5">
        <h3 className="font-semibold text-[var(--foreground)] mb-4">GMV by category</h3>
        {loading ? (
          <SkeletonBlock className="h-[220px]" />
        ) : metrics.categoryBreakdown.length === 0 ? (
          <p className="text-sm text-[var(--muted-foreground)] py-10 text-center">No orders in this date range yet.</p>
        ) : (
          <ResponsiveContainer width="100%" height={Math.max(220, metrics.categoryBreakdown.length * 34)}>
            <BarChart data={metrics.categoryBreakdown} layout="vertical" margin={{ left: 10, right: 10 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" horizontal={false} />
              <XAxis type="number" tick={{ fontSize: 10, fill: "var(--muted-foreground)" }} />
              <YAxis type="category" dataKey="category" width={140} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} />
              <Tooltip content={<ChartTooltip />} />
              <Bar dataKey="gmv" name="gmv" fill="#7A1636" radius={[0, 3, 3, 0]} />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </>
  );
}
