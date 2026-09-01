"use client";

// Typed client-side wrapper over the generic /api/proxy/* pass-through.
// Every shape here mirrors the backend's actual return type exactly (see
// backend/src/vendors, payout-accounts, uploads) — nothing here invents a
// field the backend doesn't send.

export class VendorApiError extends Error {
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
    throw new VendorApiError(res.status, message);
  }
  return data as T;
}

function extractMessage(message: unknown): string {
  return Array.isArray(message) ? message[0] : String(message);
}

export type OrderStatus = "placed" | "preparing" | "ready_for_pickup" | "picked_up" | "delivered" | "cancelled";

export interface VendorCategory {
  slug: string;
  label: string;
}

export interface Vendor {
  id: string;
  userId: string;
  businessName: string;
  category: string;
  description: string | null;
  logoUrl: string | null;
  status: "active" | "inactive";
  createdAt: string;
  commissionRateOverride: number | null;
}

export interface MenuItem {
  id: string;
  vendorId: string;
  name: string;
  description: string | null;
  price: number;
  photoUrl: string | null;
  category: string;
  isAvailable: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface OrderItemSummary {
  id: string;
  nameSnapshot: string;
  quantity: number;
  priceSnapshot: number;
  notes: string | null;
}

export interface IncomingOrder {
  id: string;
  status: OrderStatus;
  pickupCode: string;
  totalAmount: number;
  deliveryLocationLabel: string | null;
  createdAt: string;
  items: OrderItemSummary[];
}

export interface IncomingOrdersResponse {
  items: IncomingOrder[];
  total: number;
  page: number;
  limit: number;
}

export interface MetricsItem {
  menuItemId: string | null;
  name: string;
  count: number;
  revenue: number;
}

export interface Metrics {
  from: string;
  to: string;
  totalOrders: number;
  totalRevenue: number;
  mostOrderedItems: MetricsItem[];
}

export interface Bank {
  name: string;
  code: string;
}

export interface PayoutAccount {
  id: string;
  userId: string;
  bankCode: string;
  accountNumber: string;
  accountName: string;
  paystackRecipientCode: string;
  createdAt: string;
}

export interface PresignResponse {
  uploadUrl: string;
  publicUrl: string;
  expiresInSeconds: number;
}

export const vendorClient = {
  getCategories: () => proxyFetch<VendorCategory[]>("vendors/categories"),

  getVendorProfile: () => proxyFetch<Vendor>("vendors/me"),
  upsertVendorProfile: (dto: { businessName: string; category: string; description?: string; logoUrl?: string }) =>
    proxyFetch<Vendor>("vendors/me", { method: "POST", body: dto }),

  getMenu: (vendorId: string) => proxyFetch<{ vendor: Vendor; items: MenuItem[] }>(`vendors/${vendorId}/menu`),

  createMenuItem: (dto: { name: string; description?: string; price: number; photoUrl?: string; category: string }) =>
    proxyFetch<MenuItem>("vendors/me/menu-items", { method: "POST", body: dto }),
  updateMenuItem: (
    id: string,
    dto: Partial<{ name: string; description: string; price: number; photoUrl: string; category: string; isAvailable: boolean }>,
  ) => proxyFetch<MenuItem>(`vendors/me/menu-items/${id}`, { method: "PATCH", body: dto }),
  deleteMenuItem: (id: string) => proxyFetch<{ deleted: true }>(`vendors/me/menu-items/${id}`, { method: "DELETE" }),
  setAvailability: (id: string, isAvailable: boolean) =>
    proxyFetch<MenuItem>(`vendors/me/menu-items/${id}/availability`, { method: "PATCH", body: { isAvailable } }),

  getIncomingOrders: (params: { status?: OrderStatus; page?: number; limit?: number } = {}) => {
    const search = new URLSearchParams();
    if (params.status) search.set("status", params.status);
    if (params.page) search.set("page", String(params.page));
    if (params.limit) search.set("limit", String(params.limit));
    const qs = search.toString();
    return proxyFetch<IncomingOrdersResponse>(`vendors/me/orders/incoming${qs ? `?${qs}` : ""}`);
  },
  updateOrderStatus: (orderId: string, status: "preparing" | "ready_for_pickup") =>
    proxyFetch(`vendors/me/orders/${orderId}/status`, { method: "PATCH", body: { status } }),

  getMetrics: (params: { from?: string; to?: string } = {}) => {
    const search = new URLSearchParams();
    if (params.from) search.set("from", params.from);
    if (params.to) search.set("to", params.to);
    const qs = search.toString();
    return proxyFetch<Metrics>(`vendors/me/metrics${qs ? `?${qs}` : ""}`);
  },

  getBanks: () => proxyFetch<Bank[]>("payout-accounts/banks"),
  getPayoutAccount: async (userId: string): Promise<PayoutAccount | null> => {
    try {
      return await proxyFetch<PayoutAccount>(`payout-accounts/${userId}`);
    } catch (err) {
      if (err instanceof VendorApiError && err.status === 404) return null;
      throw err;
    }
  },
  savePayoutAccount: (dto: { userId: string; bankCode: string; accountNumber: string }) =>
    proxyFetch<PayoutAccount>("payout-accounts", { method: "POST", body: dto }),

  presignUpload: (dto: { contentType: "image/jpeg" | "image/png" | "image/webp"; purpose: "menu-item-photo" | "vendor-logo"; contentLengthBytes: number }) =>
    proxyFetch<PresignResponse>("uploads/presign", { method: "POST", body: dto }),
};
