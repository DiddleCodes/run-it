"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Drawer, Modal } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime } from "@/lib/format";
import { toast } from "@/lib/toast";
import { AdminApiError, AdminVendorsResponse, AdminVendorDetail, AdminVendorSummary, VendorReviewStatus, adminClient } from "@/lib/api/admin-client";

const TABS: { key: VendorReviewStatus | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "pending", label: "Pending" },
  { key: "active", label: "Approved" },
  { key: "rejected", label: "Rejected" },
  { key: "inactive", label: "Inactive" },
];

export function VendorReviewBoard({ initialData }: { initialData: AdminVendorsResponse }) {
  const [vendors, setVendors] = useState<AdminVendorSummary[]>(initialData.items);
  const [filter, setFilter] = useState<VendorReviewStatus | "all">("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminVendorDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [confirmApprove, setConfirmApprove] = useState<AdminVendorSummary | null>(null);
  const [rejectTarget, setRejectTarget] = useState<AdminVendorSummary | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const res = await adminClient.listVendors();
    setVendors(res.items);
  }

  async function openDetail(vendor: AdminVendorSummary) {
    setSelectedId(vendor.id);
    setDetailLoading(true);
    try {
      setDetail(await adminClient.getVendor(vendor.id));
    } catch {
      toast.error("Couldn't load vendor details. Please try again.");
      setSelectedId(null);
    } finally {
      setDetailLoading(false);
    }
  }

  async function approve(vendor: AdminVendorSummary) {
    setBusy(true);
    try {
      await adminClient.approveVendor(vendor.id);
      await refresh();
      if (selectedId === vendor.id) setDetail(await adminClient.getVendor(vendor.id));
      toast.success(`${vendor.businessName} approved`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't approve this vendor. Please try again.");
    } finally {
      setBusy(false);
      setConfirmApprove(null);
    }
  }

  async function reject() {
    if (!rejectTarget || !rejectReason.trim()) return;
    setBusy(true);
    try {
      await adminClient.rejectVendor(rejectTarget.id, rejectReason.trim());
      await refresh();
      if (selectedId === rejectTarget.id) setDetail(await adminClient.getVendor(rejectTarget.id));
      toast.success(`${rejectTarget.businessName} rejected`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't reject this vendor. Please try again.");
    } finally {
      setBusy(false);
      setRejectTarget(null);
      setRejectReason("");
    }
  }

  const filtered = filter === "all" ? vendors : vendors.filter((v) => v.status === filter);

  const columns: Column<AdminVendorSummary>[] = [
    { key: "businessName", header: "Business", sortable: true, render: (v) => <span className="font-medium">{v.businessName}</span> },
    { key: "category", header: "Category" },
    { key: "user", header: "Owner", render: (v) => <span className="text-sm">{v.user.name ?? v.user.email ?? "—"}</span> },
    { key: "createdAt", header: "Submitted", sortable: true, render: (v) => formatDateTime(v.createdAt) },
    { key: "status", header: "Status", render: (v) => <StatusBadge status={v.status} /> },
    {
      key: "action",
      header: "",
      render: (v) =>
        v.status === "pending" ? (
          <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={() => setConfirmApprove(v)}
              className="px-3 py-1.5 rounded-lg bg-[var(--primary)] text-white text-xs font-medium hover:bg-[#5A0E25] transition-colors"
            >
              Approve
            </button>
            <button
              onClick={() => setRejectTarget(v)}
              className="px-3 py-1.5 rounded-lg border border-red-200 text-red-600 text-xs font-medium hover:bg-red-50 transition-colors"
            >
              Reject
            </button>
          </div>
        ) : null,
    },
  ];

  return (
    <>
      <div className="flex gap-1 mb-4 flex-wrap">
        {TABS.map((t) => {
          const count = t.key === "all" ? vendors.length : vendors.filter((v) => v.status === t.key).length;
          return (
            <button
              key={t.key}
              onClick={() => setFilter(t.key)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                filter === t.key ? "bg-[var(--primary)] text-white" : "bg-card border border-[var(--border)] text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {t.label}
              <span className={`ml-1.5 px-1.5 py-0.5 rounded-full text-[10px] font-semibold ${filter === t.key ? "bg-white/20 text-white" : "bg-[var(--secondary)]"}`}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      <DataTable
        columns={columns}
        data={filtered}
        emptyTitle="No vendors here"
        emptyDescription="Vendor submissions will appear here for review."
        onRowClick={openDetail}
      />

      <Drawer
        open={!!selectedId}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedId(null);
            setDetail(null);
          }
        }}
        title={detail?.businessName ?? ""}
      >
        {detailLoading && <p className="text-sm text-[var(--muted-foreground)]">Loading…</p>}
        {detail && !detailLoading && (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <StatusBadge status={detail.status} />
              <span className="text-sm text-[var(--muted-foreground)]">Submitted {formatDateTime(detail.createdAt)}</span>
            </div>

            {detail.logoUrl && (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={detail.logoUrl} alt={detail.businessName} className="w-full h-40 object-cover rounded-xl border border-[var(--border)]" />
            )}

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Category</p>
              <p className="text-sm text-[var(--foreground)]">{detail.category}</p>
            </div>

            {detail.description && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Description</p>
                <p className="text-sm text-[var(--foreground)]">{detail.description}</p>
              </div>
            )}

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Owner</p>
              <p className="text-sm text-[var(--foreground)]">{detail.user.name ?? "—"}</p>
              <p className="text-sm text-[var(--muted-foreground)]">{detail.user.email}</p>
              <p className="text-sm text-[var(--muted-foreground)]">{detail.user.phone}</p>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Payout account</p>
              {detail.payoutAccount ? (
                <>
                  <p className="text-sm text-[var(--foreground)]">{detail.payoutAccount.accountName}</p>
                  <p className="text-sm text-[var(--muted-foreground)]">
                    {detail.payoutAccount.bankCode} •••• {detail.payoutAccount.accountNumber.slice(-4)}
                  </p>
                </>
              ) : (
                <p className="text-sm text-[var(--muted-foreground)]">Not set up yet</p>
              )}
            </div>

            {detail.rejectionReason && (
              <div className="p-3 rounded-lg bg-red-50 border border-red-200">
                <p className="text-xs font-semibold text-red-700 mb-1">Rejection reason</p>
                <p className="text-sm text-red-700">{detail.rejectionReason}</p>
              </div>
            )}

            {detail.status === "pending" && (
              <div className="flex gap-2">
                <button
                  onClick={() => setConfirmApprove(detail)}
                  className="flex-1 py-2.5 rounded-lg bg-[var(--primary)] text-white font-medium hover:bg-[#5A0E25] transition-colors"
                >
                  Approve
                </button>
                <button
                  onClick={() => setRejectTarget(detail)}
                  className="flex-1 py-2.5 rounded-lg border border-red-200 text-red-600 font-medium hover:bg-red-50 transition-colors"
                >
                  Reject
                </button>
              </div>
            )}
          </div>
        )}
      </Drawer>

      <ConfirmDialog
        open={!!confirmApprove}
        onOpenChange={(open) => !open && setConfirmApprove(null)}
        title="Approve this vendor?"
        description={`${confirmApprove?.businessName ?? ""} will become visible to students and able to receive orders.`}
        confirmLabel={busy ? "Approving…" : "Approve"}
        onConfirm={() => confirmApprove && approve(confirmApprove)}
      />

      <Modal
        open={!!rejectTarget}
        onOpenChange={(open) => {
          if (!open) {
            setRejectTarget(null);
            setRejectReason("");
          }
        }}
        title={`Reject ${rejectTarget?.businessName ?? ""}`}
        footer={
          <button
            onClick={reject}
            disabled={!rejectReason.trim() || busy}
            className="px-4 py-2 rounded-lg bg-red-600 text-white text-sm font-medium hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {busy ? "Rejecting…" : "Reject vendor"}
          </button>
        }
      >
        <div className="space-y-2">
          <label htmlFor="reject-reason" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
            Reason (shown to the restaurant)
          </label>
          <textarea
            id="reject-reason"
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
            rows={4}
            className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            placeholder="e.g. Missing business registration details"
          />
        </div>
      </Modal>
    </>
  );
}
