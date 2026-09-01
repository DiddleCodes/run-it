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
  approveVendor: (id: string) => proxyFetch<AdminVendorDetail>(`admin/vendors/${id}/approve`, { method: "POST" }),
  rejectVendor: (id: string, reason: string) =>
    proxyFetch<AdminVendorDetail>(`admin/vendors/${id}/reject`, { method: "POST", body: { reason } }),

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
};
