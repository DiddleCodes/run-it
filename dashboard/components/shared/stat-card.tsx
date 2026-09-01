import { ReactNode } from "react";

interface StatCardProps {
  icon: ReactNode;
  label: string;
  value: string | number;
  trend?: { value: number; label?: string };
  accent?: "burgundy" | "gold" | "green" | "blue";
  loading?: boolean;
}

const accentMap = {
  burgundy: { icon: "bg-[#7A1636]/10 text-[#7A1636]", bar: "bg-[#7A1636]" },
  gold: { icon: "bg-[#D99A18]/10 text-[#D99A18]", bar: "bg-[#D99A18]" },
  green: { icon: "bg-emerald-50 text-emerald-600", bar: "bg-emerald-500" },
  blue: { icon: "bg-blue-50 text-blue-600", bar: "bg-blue-500" },
};

export function StatCard({ icon, label, value, trend, accent = "burgundy", loading }: StatCardProps) {
  const ac = accentMap[accent];

  if (loading) {
    return (
      <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-5 shadow-[0_1px_8px_rgba(0,0,0,0.06)]">
        <div className="skeleton-shimmer h-4 w-24 rounded mb-3" />
        <div className="skeleton-shimmer h-8 w-32 rounded mb-2" />
        <div className="skeleton-shimmer h-3 w-16 rounded" />
      </div>
    );
  }

  const positive = trend && trend.value >= 0;

  return (
    <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-5 shadow-[0_1px_8px_rgba(0,0,0,0.06)] hover:shadow-[0_4px_16px_rgba(0,0,0,0.1)] transition-shadow group relative overflow-hidden">
      <div className={`absolute top-0 left-0 h-0.5 w-full ${ac.bar} opacity-60`} />
      <div className="flex items-start justify-between mb-3">
        <span className={`inline-flex p-2 rounded-lg ${ac.icon} transition-transform group-hover:scale-110`}>{icon}</span>
        {trend && (
          <span className={`text-xs font-medium flex items-center gap-0.5 ${positive ? "text-emerald-600" : "text-red-500"}`}>
            <span>{positive ? "▲" : "▼"}</span>
            {Math.abs(trend.value)}%
          </span>
        )}
      </div>
      <div className="text-2xl font-semibold text-[var(--foreground)] leading-tight mb-0.5">{value}</div>
      <div className="text-sm text-[var(--muted-foreground)]">{label}</div>
      {trend?.label && <div className="text-[11px] text-[var(--muted-foreground)] mt-1 opacity-70">{trend.label}</div>}
    </div>
  );
}
