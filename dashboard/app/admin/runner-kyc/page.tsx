import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { RunnerKycReviewBoard } from "@/components/admin/runner-kyc-review-board";
import type { AdminRunnerKycResponse } from "@/lib/api/admin-client";

export default async function RunnerKycReviewPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<AdminRunnerKycResponse>("/admin/runner-kyc", { token: token! });

  return (
    <>
      <PageHeader title="Runner KYC" subtitle="Approve or reject runner identity/vehicle submissions." breadcrumb="Admin" />
      <RunnerKycReviewBoard initialData={initialData} />
    </>
  );
}
