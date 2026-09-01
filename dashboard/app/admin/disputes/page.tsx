import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { DisputesBoard } from "@/components/admin/disputes-board";
import type { AdminDisputeSummary } from "@/lib/api/admin-client";

export default async function DisputesPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<AdminDisputeSummary[]>("/admin/disputes", { token: token! });

  return (
    <>
      <PageHeader title="Disputes" subtitle="Review and resolve flagged orders." breadcrumb="Admin" />
      <DisputesBoard initialData={initialData} />
    </>
  );
}
