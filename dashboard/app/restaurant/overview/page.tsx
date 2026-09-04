import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { StatCard } from "@/components/shared/stat-card";
import { formatKobo } from "@/lib/format";
import type { IncomingOrdersResponse, Metrics, MenuItem, Vendor } from "@/lib/api/vendor-client";

export default async function RestaurantOverviewPage() {
  const token = await getSessionToken();

  const vendor = await backendFetch<Vendor>("/vendors/me", { token: token! });

  const startOfToday = new Date();
  startOfToday.setHours(0, 0, 0, 0);

  const [menu, incoming, metrics] = await Promise.all([
    backendFetch<{ vendor: Vendor; items: MenuItem[] }>(`/vendors/${vendor.id}/menu`, { token: token! }),
    backendFetch<IncomingOrdersResponse>("/vendors/me/orders/incoming?limit=1", { token: token! }),
    backendFetch<Metrics>(`/vendors/me/metrics?from=${startOfToday.toISOString()}&to=${new Date().toISOString()}`, {
      token: token!,
    }),
  ]);

  const availableCount = menu.items.filter((i) => i.isAvailable).length;

  return (
    <>
      <PageHeader title="Overview" subtitle="Your restaurant's activity at a glance." breadcrumb="Restaurant" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon={<span />} label="Today's orders" value={metrics.totalOrders} accent="burgundy" />
        <StatCard icon={<span />} label="Today's revenue" value={formatKobo(metrics.totalRevenue)} accent="gold" />
        <StatCard icon={<span />} label="Open orders" value={incoming.total} accent="blue" />
        <StatCard icon={<span />} label="Menu items live" value={`${availableCount} / ${menu.items.length}`} accent="green" />
      </div>
      <p className="text-sm text-[var(--muted-foreground)] mt-6">Figures reflect today so far. See Metrics for a date-range view.</p>
    </>
  );
}
