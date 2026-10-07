import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { EarningsBoard } from "@/components/vendor/earnings-board";
import type { Earnings } from "@/lib/api/vendor-client";

export default async function RestaurantEarningsPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<Earnings>("/vendors/me/earnings", { token: token! });

  return (
    <>
      <PageHeader title="Earnings" subtitle="What you've been paid, and what's on its way." breadcrumb="Restaurant" />
      <EarningsBoard initialData={initialData} />
    </>
  );
}
