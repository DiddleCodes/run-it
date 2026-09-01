import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { MetricsBoard } from "@/components/vendor/metrics-board";
import type { Metrics } from "@/lib/api/vendor-client";

export default async function RestaurantMetricsPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<Metrics>("/vendors/me/metrics", { token: token! });

  return (
    <>
      <PageHeader title="Metrics" subtitle="Performance insights for your restaurant." breadcrumb="Restaurant" />
      <MetricsBoard initialData={initialData} />
    </>
  );
}
