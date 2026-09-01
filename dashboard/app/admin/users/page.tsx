import { backendFetch } from "@/lib/api/backend-client";
import { getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { UsersBoard } from "@/components/admin/users-board";
import type { AdminUsersResponse } from "@/lib/api/admin-client";

export default async function UsersPage() {
  const token = await getSessionToken();
  const initialData = await backendFetch<AdminUsersResponse>("/admin/users", { token: token! });

  return (
    <>
      <PageHeader title="Users" subtitle="Search, suspend, and reinstate accounts." breadcrumb="Admin" />
      <UsersBoard initialData={initialData} />
    </>
  );
}
