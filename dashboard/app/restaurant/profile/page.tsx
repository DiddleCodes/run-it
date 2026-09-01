import { BackendApiError, backendFetch } from "@/lib/api/backend-client";
import { getSession, getSessionToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/layout/page-header";
import { ProfileBoard } from "@/components/vendor/profile-board";
import type { PayoutAccount, Vendor } from "@/lib/api/vendor-client";

async function fetchOrNull<T>(path: string, token: string): Promise<T | null> {
  try {
    return await backendFetch<T>(path, { token });
  } catch (err) {
    if (err instanceof BackendApiError && err.status === 404) return null;
    throw err;
  }
}

export default async function RestaurantProfilePage() {
  const [session, token] = await Promise.all([getSession(), getSessionToken()]);
  const [vendor, payoutAccount] = await Promise.all([
    fetchOrNull<Vendor>("/vendors/me", token!),
    fetchOrNull<PayoutAccount>(`/payout-accounts/${session!.sub}`, token!),
  ]);

  return (
    <>
      <PageHeader title="Restaurant Profile" subtitle="Manage your business info and payout details." breadcrumb="Restaurant" />
      <ProfileBoard userId={session!.sub} initialVendor={vendor} initialPayoutAccount={payoutAccount} />
    </>
  );
}
