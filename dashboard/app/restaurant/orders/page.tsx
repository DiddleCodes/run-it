import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { OrdersBoard } from "@/components/vendor/orders-board";
import type { IncomingOrdersResponse } from "@/lib/api/vendor-client";

export default async function RestaurantOrdersPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<IncomingOrdersResponse>("/vendors/me/orders/incoming", { token: token! });

  return (
    <>
      <PageHeader title="Orders" subtitle="Live queue for your kitchen." breadcrumb="Restaurant" />
      <OrdersBoard initialData={initialData} />
    </>
  );
}
