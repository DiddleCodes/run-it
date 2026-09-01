import { BackendApiError, backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { ReconciliationBoard } from "@/components/admin/reconciliation-board";
import type { ReconciliationReport, ReconciliationRun } from "@/lib/api/admin-client";

// The report depends on a live Paystack call (unlike every other admin
// page) — if Paystack is unreachable or misconfigured, the page should
// show a clear inline error, not hard-crash the whole route. History is
// pure local data and always expected to load.
async function fetchReportOrNull(token: string): Promise<ReconciliationReport | null> {
  try {
    return await backendFetch<ReconciliationReport>("/reconciliation/report", { token });
  } catch (err) {
    if (err instanceof BackendApiError) return null;
    throw err;
  }
}

export default async function ReconciliationPage() {
  const token = await getSessionToken();
  const [initialData, initialHistory] = await Promise.all([
    fetchReportOrNull(token!),
    backendFetch<ReconciliationRun[]>("/reconciliation/history", { token: token! }),
  ]);

  return (
    <>
      <PageHeader title="Reconciliation" subtitle="Compare platform records against Paystack." breadcrumb="Admin" />
      <ReconciliationBoard initialData={initialData} initialHistory={initialHistory} />
    </>
  );
}
