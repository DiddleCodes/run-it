import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { CampusesBoard } from "@/components/admin/campuses-board";
import type { AdminCampusDetail } from "@/lib/api/admin-client";

export default async function CampusesPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<AdminCampusDetail[]>("/admin/campuses", { token: token! });

  return (
    <>
      <PageHeader title="Campuses" subtitle="Add, edit, and manage which schools can sign up." breadcrumb="Admin" />
      <CampusesBoard initialData={initialData} />
    </>
  );
}
