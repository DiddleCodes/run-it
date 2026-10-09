import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { MenuAnalyticsBoard } from "@/components/admin/menu-analytics-board";
import type { MenuAnalytics } from "@/lib/api/admin-client";

export default async function AnalyticsPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<MenuAnalytics>("/admin/analytics/menu", { token: token! });

  return (
    <>
      <PageHeader
        title="Analytics"
        subtitle="Which dishes, at which restaurants, earn the most — delivered orders only, after Bridgit's cut."
        breadcrumb="Admin"
      />
      <MenuAnalyticsBoard initialData={initialData} />
    </>
  );
}
