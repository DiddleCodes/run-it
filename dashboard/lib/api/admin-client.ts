"use client";

// Typed client-side wrapper over the generic /api/proxy/* pass-through, for
// the /admin/* backend routes (Task 13c). Same proxyFetch pattern as
// lib/api/vendor-client.ts — every shape here mirrors the backend's actual
// return type exactly.

export class AdminApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

async function proxyFetch<T>(path: string, options: { method?: string; body?: unknown } = {}): Promise<T> {
  const res = await fetch(`/api/proxy/${path}`, {
    method: options.method ?? "GET",
    headers: { "Content-Type": "application/json" },
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });

  const contentType = res.headers.get("content-type") ?? "";
  const data = contentType.includes("application/json") ? await res.json() : await res.text();

  if (!res.ok) {
    const message = typeof data === "object" && data && "message" in data ? extractMessage(data.message) : "Request failed";
    throw new AdminApiError(res.status, message);
  }
  return data as T;
}

function extractMessage(message: unknown): string {
  return Array.isArray(message) ? message[0] : String(message);
}

export type VendorReviewStatus = "pending" | "active" | "rejected" | "inactive";

export interface AdminPayoutAccount {
  bankCode: string;
  accountNumber: string;
  accountName: string;
}

export interface AdminCampus {
  id: string;
  name: string;
}

export interface AdminVendorSummary {
  id: string;
  userId: string;
  businessName: string;
  category: string;
  description: string | null;
  logoUrl: string | null;
  status: VendorReviewStatus;
  rejectionReason: string | null;
  createdAt: string;
  commissionRateOverride: number | null;
  user: { name: string | null; email: string | null; phone: string | null };
  // Task 27: the applicant's own stated preference from the mobile wizard —
  // informational only, pre-fills (never dictates) the campus picker below.
  requestedCampus: AdminCampus | null;
}

export interface AdminVendorDetail extends AdminVendorSummary {
  user: { name: string | null; email: string | null; phone: string | null; createdAt: string };
  payoutAccount: AdminPayoutAccount | null;
}

export interface AdminVendorsResponse {
  items: AdminVendorSummary[];
  total: number;
  page: number;
  limit: number;
}

export type DisputeStatus = "open" | "resolved";
export type DisputeResolutionType = "release" | "refund" | "deny";

export interface AdminDisputeOrderSummary {
  id: string;
  status: string;
  totalAmount: number;
  deliveryLocationLabel: string | null;
}

export interface AdminDisputeSummary {
  id: string;
  orderId: string;
  status: DisputeStatus;
  reason: string;
  // Task 30: set when a student filed this via POST /orders/:orderId/report
  // (their own optional photo evidence) — null for the auto-opened
  // delivery-proof-unavailable path and any admin-manual open().
  reporterPhotoUrl: string | null;
  resolutionType: DisputeResolutionType | null;
  resolutionNote: string | null;
  resolvedBy: string | null;
  resolvedAt: string | null;
  openedAt: string;
  order: AdminDisputeOrderSummary;
}

export interface AdminDisputeOrderItem {
  id: string;
  nameSnapshot: string;
  quantity: number;
  priceSnapshot: number;
}

export interface AdminDisputeOrderDetail extends AdminDisputeOrderSummary {
  deliveryProofUrl: string | null;
  // Task 30: the runner's required restaurant-handoff photo, captured at
  // pickup-PIN verification — real for every order past `picked_up` now.
  handoffPhotoUrl: string | null;
  vendor: { id: string; businessName: string };
  studentUser: { id: string; name: string | null; phone: string | null };
  runnerUser: { id: string; name: string | null; phone: string | null } | null;
  items: AdminDisputeOrderItem[];
  escrow: { grossAmount: number; platformFee: number; restaurantShare: number; runnerShare: number; status: string } | null;
}

export interface AdminDisputeDetail extends Omit<AdminDisputeSummary, "order"> {
  order: AdminDisputeOrderDetail;
}

export interface PlatformCategoryBreakdown {
  category: string;
  gmv: number;
}

export interface PlatformMetrics {
  from: string;
  to: string;
  gmv: number;
  orderVolume: number;
  activeVendors: number;
  activeRunners: number;
  platformRevenue: number;
  takeRatePct: number;
  categoryBreakdown: PlatformCategoryBreakdown[];
}

export type ReconciliationMismatchKind = "missing_locally" | "missing_on_paystack" | "amount_mismatch" | "status_mismatch";
export type ReconciliationEntryType = "wallet_topup" | "transfer";

export interface ReconciliationMismatch {
  reference: string;
  type: ReconciliationEntryType;
  kind: ReconciliationMismatchKind;
  localAmount: number | null;
  paystackAmount: number | null;
  localStatus: string | null;
  paystackStatus: string | null;
  resolved: boolean;
}

export interface ReconciliationReport {
  from: string;
  to: string;
  summary: {
    matched: number;
    missingLocally: number;
    missingOnPaystack: number;
    amountMismatch: number;
    statusMismatch: number;
  };
  mismatches: ReconciliationMismatch[];
}

export interface ReconciliationRun {
  id: string;
  startedAt: string;
  finishedAt: string;
  walletChecked: number;
  transferLegsChecked: number;
  mismatchCount: number;
  triggeredBy: string | null;
}

// Task 29: mirrors VendorReviewStatus's own shape — see RunnerKycStatus on
// the backend.
export type RunnerKycReviewStatus = "pending" | "approved" | "rejected";
export type RunnerKycRunnerType = "student_runner" | "independent_rider";
export type RunnerKycIdType = "student_id" | "government_id";
export type RunnerVehicleType = "bicycle" | "motorbike" | "keke";

export interface AdminRunnerKycSummary {
  id: string;
  userId: string;
  runnerType: RunnerKycRunnerType | null;
  idType: RunnerKycIdType | null;
  idPhotoUrl: string | null;
  selfiePhotoUrl: string | null;
  vehiclePhotoUrl: string | null;
  vehicleType: RunnerVehicleType | null;
  vehiclePlate: string | null;
  status: RunnerKycReviewStatus;
  rejectionReason: string | null;
  submittedAt: string;
  reviewedAt: string | null;
  user: { name: string | null; email: string | null; phone: string | null };
}

export interface AdminRunnerKycDetail extends AdminRunnerKycSummary {
  user: { name: string | null; email: string | null; phone: string | null; createdAt: string };
}

export interface AdminRunnerKycResponse {
  items: AdminRunnerKycSummary[];
  total: number;
  page: number;
  limit: number;
}

export type AccountType = "student" | "runner" | "restaurant" | "admin";

export interface AdminUserSummary {
  id: string;
  email: string | null;
  phone: string | null;
  name: string | null;
  accountType: AccountType;
  suspendedAt: string | null;
  createdAt: string;
}

export interface AdminUserDetail extends AdminUserSummary {
  vendor: { id: string; businessName: string; status: string } | null;
  wallet: { balance: number } | null;
}

export interface AdminUsersResponse {
  items: AdminUserSummary[];
  total: number;
  page: number;
  limit: number;
}

export const adminClient = {
  listVendors: (params: { status?: VendorReviewStatus; page?: number; limit?: number } = {}) => {
    const search = new URLSearchParams();
    if (params.status) search.set("status", params.status);
    if (params.page) search.set("page", String(params.page));
    if (params.limit) search.set("limit", String(params.limit));
    const qs = search.toString();
    return proxyFetch<AdminVendorsResponse>(`admin/vendors${qs ? `?${qs}` : ""}`);
  },
  getVendor: (id: string) => proxyFetch<AdminVendorDetail>(`admin/vendors/${id}`),
  // Task 27: campusId is optional — omitting it approves with no campus
  // assignment, same as before this task (the generic PATCH
  // /admin/users/:id/campus route still covers assigning one later).
  approveVendor: (id: string, campusId?: string) =>
    proxyFetch<AdminVendorDetail>(`admin/vendors/${id}/approve`, { method: "POST", body: campusId ? { campusId } : undefined }),
  rejectVendor: (id: string, reason: string) =>
    proxyFetch<AdminVendorDetail>(`admin/vendors/${id}/reject`, { method: "POST", body: { reason } }),
  // Public backend route, proxied like everything else so the dashboard
  // never talks to BACKEND_URL directly (see route.ts's own doc comment).
  listCampuses: () => proxyFetch<AdminCampus[]>("campuses"),

  listDisputes: (status?: DisputeStatus) =>
    proxyFetch<AdminDisputeSummary[]>(`admin/disputes${status ? `?status=${status}` : ""}`),
  getDispute: (id: string) => proxyFetch<AdminDisputeDetail>(`admin/disputes/${id}`),
  resolveDispute: (id: string, resolutionType: DisputeResolutionType, note?: string) =>
    proxyFetch<AdminDisputeDetail>(`admin/disputes/${id}/resolve`, { method: "POST", body: { resolutionType, note } }),

  getPlatformMetrics: (params: { from?: string; to?: string } = {}) => {
    const search = new URLSearchParams();
    if (params.from) search.set("from", params.from);
    if (params.to) search.set("to", params.to);
    const qs = search.toString();
    return proxyFetch<PlatformMetrics>(`admin/metrics${qs ? `?${qs}` : ""}`);
  },

  getReconciliationReport: (params: { from?: string; to?: string } = {}) => {
    const search = new URLSearchParams();
    if (params.from) search.set("from", params.from);
    if (params.to) search.set("to", params.to);
    const qs = search.toString();
    return proxyFetch<ReconciliationReport>(`reconciliation/report${qs ? `?${qs}` : ""}`);
  },
  resolveMismatch: (reference: string, note: string) =>
    proxyFetch<{ reference: string }>(`reconciliation/${encodeURIComponent(reference)}/resolve`, { method: "POST", body: { note } }),
  getReconciliationHistory: () => proxyFetch<ReconciliationRun[]>("reconciliation/history"),

  listUsers: (params: { search?: string; accountType?: AccountType; page?: number; limit?: number } = {}) => {
    const search = new URLSearchParams();
    if (params.search) search.set("search", params.search);
    if (params.accountType) search.set("accountType", params.accountType);
    if (params.page) search.set("page", String(params.page));
    if (params.limit) search.set("limit", String(params.limit));
    const qs = search.toString();
    return proxyFetch<AdminUsersResponse>(`admin/users${qs ? `?${qs}` : ""}`);
  },
  getUser: (id: string) => proxyFetch<AdminUserDetail>(`admin/users/${id}`),
  suspendUser: (id: string, reason: string) =>
    proxyFetch<AdminUserDetail>(`admin/users/${id}/suspend`, { method: "POST", body: { reason } }),
  reinstateUser: (id: string) => proxyFetch<AdminUserDetail>(`admin/users/${id}/reinstate`, { method: "POST" }),

  listRunnerKyc: (params: { status?: RunnerKycReviewStatus; page?: number; limit?: number } = {}) => {
    const search = new URLSearchParams();
    if (params.status) search.set("status", params.status);
    if (params.page) search.set("page", String(params.page));
    if (params.limit) search.set("limit", String(params.limit));
    const qs = search.toString();
    return proxyFetch<AdminRunnerKycResponse>(`admin/runner-kyc${qs ? `?${qs}` : ""}`);
  },
  getRunnerKyc: (id: string) => proxyFetch<AdminRunnerKycDetail>(`admin/runner-kyc/${id}`),
  approveRunnerKyc: (id: string) => proxyFetch<AdminRunnerKycDetail>(`admin/runner-kyc/${id}/approve`, { method: "POST" }),
  rejectRunnerKyc: (id: string, reason: string) =>
    proxyFetch<AdminRunnerKycDetail>(`admin/runner-kyc/${id}/reject`, { method: "POST", body: { reason } }),
};
