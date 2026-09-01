import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { PlatformMetricsBoard } from "@/components/admin/platform-metrics-board";
import type { PlatformMetrics } from "@/lib/api/admin-client";

export default async function PlatformMetricsPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<PlatformMetrics>("/admin/metrics", { token: token! });

  return (
    <>
      <PageHeader title="Platform Metrics" subtitle="GMV, order volume, and take rate across RUN-It." breadcrumb="Admin" />
      <PlatformMetricsBoard initialData={initialData} />
    </>
  );
}
