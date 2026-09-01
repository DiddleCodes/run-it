import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { MenuBoard } from "@/components/vendor/menu-board";
import type { MenuItem, Vendor } from "@/lib/api/vendor-client";

export default async function RestaurantMenuPage() {
  const token = await getSessionToken();
  const vendor = await backendFetch<Vendor>("/vendors/me", { token: token! });
  const { items } = await backendFetch<{ vendor: Vendor; items: MenuItem[] }>(`/vendors/${vendor.id}/menu`, { token: token! });

  return (
    <>
      <PageHeader title="Menu" subtitle={`${items.length} items · ${items.filter((i) => i.isAvailable).length} available`} breadcrumb="Restaurant" />
      <MenuBoard vendorId={vendor.id} initialItems={items} />
    </>
  );
}
