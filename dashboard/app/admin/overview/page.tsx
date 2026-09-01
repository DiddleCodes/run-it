import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { StatCard } from "@/components/shared/stat-card";
import { formatKobo } from "@/lib/format";
import type { AdminDisputeSummary, PlatformMetrics } from "@/lib/api/admin-client";

export default async function AdminOverviewPage() {
  const token = await getSessionToken();
  const [metrics, disputes] = await Promise.all([
    backendFetch<PlatformMetrics>("/admin/metrics", { token: token! }),
    backendFetch<AdminDisputeSummary[]>("/admin/disputes?status=open", { token: token! }),
  ]);

  return (
    <>
      <PageHeader title="Overview" subtitle="Platform-wide activity at a glance." breadcrumb="Admin" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon={<span />} label="Platform GMV" value={formatKobo(metrics.gmv)} accent="burgundy" />
        <StatCard icon={<span />} label="Total orders" value={metrics.orderVolume} accent="gold" />
        <StatCard icon={<span />} label="Active vendors" value={metrics.activeVendors} accent="green" />
        <StatCard icon={<span />} label="Open disputes" value={disputes.length} accent="blue" />
      </div>
      <p className="text-sm text-[var(--muted-foreground)] mt-6">Figures reflect the last 30 days. See Platform Metrics for a date-range view.</p>
    </>
  );
}
