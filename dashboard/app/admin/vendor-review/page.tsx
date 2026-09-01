import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { VendorReviewBoard } from "@/components/admin/vendor-review-board";
import type { AdminVendorsResponse } from "@/lib/api/admin-client";

export default async function VendorReviewPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<AdminVendorsResponse>("/admin/vendors", { token: token! });

  return (
    <>
      <PageHeader title="Vendor Review" subtitle="Approve or reject restaurant submissions." breadcrumb="Admin" />
      <VendorReviewBoard initialData={initialData} />
    </>
  );
}
