"use client";

import { useState } from "react";
import { Banknote, Info, ShoppingBag, Store, TrendingUp, TriangleAlert, UtensilsCrossed } from "lucide-react";
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { Column, DataTable } from "@/components/shared/data-table";
import { StatCard } from "@/components/shared/stat-card";
import { formatKobo, formatKoboCompact } from "@/lib/format";
import { useIsPhone } from "@/lib/hooks/use-is-phone";
import { adminClient, MenuAnalytics, MenuAnalyticsDish, MenuAnalyticsRestaurant, MenuInsight } from "@/lib/api/admin-client";

const RANGES = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];
const DAY_MS = 24 * 60 * 60 * 1000;
const CHART_DISHES = 10;

// Custom dates are whole days in Lagos, like the restaurant Earnings page.
const lagosDayStart = (date: string) => new Date(`${date}T00:00:00+01:00`).toISOString();
const lagosDayEnd = (date: string) => new Date(`${date}T23:59:59.999+01:00`).toISOString();

const TONE: Record<MenuInsight["tone"], { box: string; icon: React.ReactNode }> = {
  positive: { box: "border-emerald-200 bg-emerald-50 text-emerald-900", icon: <TrendingUp size={16} className="text-emerald-600" /> },
  warning: { box: "border-amber-200 bg-amber-50 text-amber-900", icon: <TriangleAlert size={16} className="text-amber-600" /> },
  info: { box: "border-[var(--border)] bg-card text-[var(--foreground)]", icon: <Info size={16} className="text-slate-500" /> },
};

function Change({ dish }: { dish: MenuAnalyticsDish }) {
  if (dish.changePct === null) {
    return <span className="text-xs font-medium text-emerald-700">{dish.previousQuantity === 0 ? "New" : "—"}</span>;
  }
  const up = dish.changePct >= 0;
  return (
    <span className={`text-xs font-semibold tabular-nums ${up ? "text-emerald-700" : "text-red-600"}`}>
      {up ? "▲" : "▼"} {Math.abs(dish.changePct)}%
    </span>
  );
}

export function MenuAnalyticsBoard({ initialData }: { initialData: MenuAnalytics }) {
  const [data, setData] = useState<MenuAnalytics>(initialData);
  const [rangeDays, setRangeDays] = useState<number | null>(30);
  const [range, setRange] = useState<{ from: string; to: string } | null>(null);
  const [vendorId, setVendorId] = useState("");
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const isPhone = useIsPhone();

  async function load(next: { from: string; to: string } | null, nextVendorId: string) {
    setLoading(true);
    setFailed(false);
    try {
      setData(await adminClient.getMenuAnalytics({ ...(next ?? {}), vendorId: nextVendorId || undefined }));
    } catch {
      setFailed(true);
    } finally {
      setLoading(false);
    }
  }

  function selectPreset(days: number) {
    setRangeDays(days);
    const to = new Date();
    const next = { from: new Date(to.getTime() - days * DAY_MS).toISOString(), to: to.toISOString() };
    setRange(next);
    void load(next, vendorId);
  }

  function applyCustom() {
    if (!customFrom || !customTo || customFrom > customTo) return;
    setRangeDays(null);
    const next = { from: lagosDayStart(customFrom), to: lagosDayEnd(customTo) };
    setRange(next);
    void load(next, vendorId);
  }

  function selectRestaurant(id: string) {
    setVendorId(id);
    void load(range, id);
  }

  const { totals } = data;
  const chartData = data.dishes.slice(0, CHART_DISHES).map((d) => ({
    // Phones: dish names only — the restaurant is on each dish's card below.
    label: data.vendorId || isPhone ? d.name : `${d.name} · ${d.restaurantName}`,
    earned: d.earnedKobo,
  }));

  const dishColumns: Column<MenuAnalyticsDish & { id: string; rank: number }>[] = [
    { key: "rank", header: "#", phoneHidden: true, render: (d) => <span className="tabular-nums text-[var(--muted-foreground)]">{d.rank}</span> },
    { key: "name", header: "Dish", phoneTitle: true, render: (d) => <span className="font-semibold text-[var(--foreground)]">{d.name}</span> },
    { key: "restaurantName", header: "Restaurant", render: (d) => d.restaurantName },
    { key: "quantity", header: "Sold", align: "right", sortable: true, render: (d) => d.quantity },
    { key: "salesKobo", header: "Sales", align: "right", sortable: true, render: (d) => formatKobo(d.salesKobo) },
    {
      key: "earnedKobo",
      header: "Restaurant earned",
      align: "right",
      sortable: true,
      render: (d) => <span className="font-semibold text-[var(--foreground)]">{formatKobo(d.earnedKobo)}</span>,
    },
    { key: "shareOfRestaurantPct", header: "Share of restaurant", align: "right", render: (d) => `${d.shareOfRestaurantPct}%` },
    { key: "changePct", header: "vs previous period", align: "right", render: (d) => <Change dish={d} /> },
  ];

  const restaurantColumns: Column<MenuAnalyticsRestaurant & { id: string }>[] = [
    { key: "name", header: "Restaurant", render: (r) => <span className="font-semibold text-[var(--foreground)]">{r.name}</span> },
    { key: "orders", header: "Orders", align: "right", sortable: true, render: (r) => r.orders },
    { key: "salesKobo", header: "Sales", align: "right", sortable: true, render: (r) => formatKobo(r.salesKobo) },
    {
      key: "earnedKobo",
      header: "Earned",
      align: "right",
      sortable: true,
      render: (r) => <span className="font-semibold text-[var(--foreground)]">{formatKobo(r.earnedKobo)}</span>,
    },
    {
      key: "topDish",
      header: "Best seller",
      render: (r) =>
        r.topDish ? (
          <span>
            {r.topDish.name} <span className="text-xs text-[var(--muted-foreground)]">({r.topDish.sharePct}% of earnings)</span>
          </span>
        ) : (
          "—"
        ),
    },
    {
      key: "unordered",
      header: "Dishes not ordered",
      align: "right",
      render: (r) => (r.unorderedDishes.length ? <span title={r.unorderedDishes.join(", ")}>{r.unorderedDishes.length}</span> : "0"),
    },
  ];

  return (
    <>
      <div className="flex flex-wrap items-center justify-start sm:justify-end gap-3 mb-6">
        <label className="flex items-center gap-2 text-xs text-[var(--muted-foreground)]">
          Restaurant
          <select
            aria-label="Restaurant"
            value={vendorId}
            onChange={(e) => selectRestaurant(e.target.value)}
            className="rounded-md border border-[var(--border)] bg-card px-2 py-1 text-sm text-[var(--foreground)]"
          >
            <option value="">All restaurants</option>
            {data.restaurantOptions.map((r) => (
              <option key={r.id} value={r.id}>
                {r.name}
              </option>
            ))}
          </select>
        </label>
        <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--muted-foreground)]">
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

      {failed && (
        <p role="alert" className="mb-4 text-sm text-red-600">
          Couldn&apos;t load analytics for that selection. Try again.
        </p>
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 mb-6">
        <StatCard icon={<Banknote size={16} />} label="Restaurants earned (after Bridgit's cut)" value={loading ? "" : formatKobo(totals.earnedKobo)} accent="green" loading={loading} />
        <StatCard icon={<ShoppingBag size={16} />} label="Food sales" value={loading ? "" : formatKobo(totals.salesKobo)} accent="burgundy" loading={loading} />
        <StatCard icon={<UtensilsCrossed size={16} />} label="Dishes sold" value={loading ? "" : totals.itemsSold.toLocaleString("en-NG")} accent="gold" loading={loading} />
        <StatCard
          icon={<Store size={16} />}
          label={`Delivered orders · ${totals.restaurants} ${totals.restaurants === 1 ? "restaurant" : "restaurants"}`}
          value={loading ? "" : totals.orders.toLocaleString("en-NG")}
          accent="blue"
          loading={loading}
        />
      </div>

      <section aria-labelledby="insights-heading" className="mb-6">
        <h2 id="insights-heading" className="font-fraunces text-lg font-semibold mb-3">
          Insights
        </h2>
        {loading ? (
          <div className="skeleton-shimmer h-24 rounded-xl" />
        ) : (
          <ul className="grid grid-cols-1 lg:grid-cols-2 gap-3">
            {data.insights.map((insight, i) => (
              <li key={`${insight.kind}-${i}`} className={`flex gap-3 rounded-xl border px-4 py-3 ${TONE[insight.tone].box}`}>
                <span className="mt-0.5 shrink-0">{TONE[insight.tone].icon}</span>
                <div>
                  <p className="text-sm font-semibold">{insight.title}</p>
                  <p className="text-sm opacity-90">{insight.detail}</p>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {chartData.length > 0 && !loading && (
        <section aria-labelledby="chart-heading" className="mb-6 rounded-xl border border-[var(--border)] bg-card p-4">
          <h2 id="chart-heading" className="text-sm font-semibold mb-3">
            Top {chartData.length} dishes by what they earned the restaurant
          </h2>
          <div style={{ height: Math.max(chartData.length * 34, 120) }}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartData} layout="vertical" margin={{ left: 8, right: 24 }}>
                <CartesianGrid horizontal={false} strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis type="number" tickFormatter={(v: number) => formatKoboCompact(v)} tick={{ fontSize: 11 }} />
                <YAxis type="category" dataKey="label" width={isPhone ? 110 : 220} tick={{ fontSize: 11 }} />
                <Tooltip formatter={(v) => formatKobo(Number(v))} labelStyle={{ fontWeight: 600 }} />
                <Bar dataKey="earned" name="Restaurant earned" fill="#7A1636" radius={[0, 4, 4, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </section>
      )}

      <section aria-labelledby="dishes-heading" className="mb-6">
        <h2 id="dishes-heading" className="font-fraunces text-lg font-semibold mb-3">
          Top dishes
        </h2>
        <DataTable
          columns={dishColumns}
          data={data.dishes.map((d, i) => ({ ...d, id: d.key, rank: i + 1 }))}
          loading={loading}
          emptyTitle="No dishes sold in this period"
          emptyDescription="Delivered orders will show their dishes here."
        />
      </section>

      {!data.vendorId && (
        <section aria-labelledby="restaurants-heading">
          <h2 id="restaurants-heading" className="font-fraunces text-lg font-semibold mb-3">
            Restaurants
          </h2>
          <DataTable
            columns={restaurantColumns}
            data={data.restaurants.map((r) => ({ ...r, id: r.vendorId }))}
            loading={loading}
            emptyTitle="No restaurant sales in this period"
            emptyDescription="Restaurants appear once they've delivered an order."
          />
        </section>
      )}
    </>
  );
}
