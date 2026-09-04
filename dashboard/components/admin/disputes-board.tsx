"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Drawer, Modal } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime, formatKobo } from "@/lib/format";
import { toast } from "@/lib/toast";
import {
  AdminApiError,
  AdminDisputeDetail,
  AdminDisputeSummary,
  DisputeResolutionType,
  DisputeStatus,
  adminClient,
} from "@/lib/api/admin-client";

const TABS: { key: DisputeStatus | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "open", label: "Open" },
  { key: "resolved", label: "Resolved" },
];

const RESOLUTION_OPTIONS: { key: DisputeResolutionType; label: string; description: string }[] = [
  { key: "release", label: "Release", description: "Delivery confirmed — pay the restaurant and runner." },
  { key: "refund", label: "Refund", description: "Return the funds to the student. Only possible while escrow is still held." },
  { key: "deny", label: "Deny", description: "Close with no money movement." },
];

export function DisputesBoard({ initialData }: { initialData: AdminDisputeSummary[] }) {
  const [disputes, setDisputes] = useState<AdminDisputeSummary[]>(initialData);
  const [filter, setFilter] = useState<DisputeStatus | "all">("open");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminDisputeDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [resolving, setResolving] = useState<AdminDisputeSummary | null>(null);
  const [resolutionType, setResolutionType] = useState<DisputeResolutionType>("release");
  const [note, setNote] = useState("");
  const [confirmResolve, setConfirmResolve] = useState(false);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    setDisputes(await adminClient.listDisputes());
  }

  async function openDetail(dispute: AdminDisputeSummary) {
    setSelectedId(dispute.id);
    setDetailLoading(true);
    try {
      setDetail(await adminClient.getDispute(dispute.id));
    } catch {
      toast.error("Couldn't load dispute details. Please try again.");
      setSelectedId(null);
    } finally {
      setDetailLoading(false);
    }
  }

  async function resolve() {
    if (!resolving) return;
    setBusy(true);
    try {
      await adminClient.resolveDispute(resolving.id, resolutionType, note.trim() || undefined);
      await refresh();
      if (selectedId === resolving.id) setDetail(await adminClient.getDispute(resolving.id));
      toast.success(`Dispute resolved as "${resolutionType}"`);
      setResolving(null);
      setNote("");
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't resolve this dispute. Please try again.");
    } finally {
      setBusy(false);
      setConfirmResolve(false);
    }
  }

  const filtered = filter === "all" ? disputes : disputes.filter((d) => d.status === filter);

  const columns: Column<AdminDisputeSummary>[] = [
    { key: "orderId", header: "Order", render: (d) => <span className="font-mono text-xs">{d.orderId.slice(0, 8)}</span> },
    { key: "reason", header: "Reason", render: (d) => <span className="text-sm">{d.reason}</span> },
    { key: "totalAmount", header: "Amount", render: (d) => formatKobo(d.order.totalAmount) },
    { key: "openedAt", header: "Opened", sortable: true, render: (d) => formatDateTime(d.openedAt) },
    { key: "status", header: "Status", render: (d) => <StatusBadge status={d.status} /> },
    {
      key: "action",
      header: "",
      render: (d) =>
        d.status === "open" ? (
          <button
            onClick={(e) => {
              e.stopPropagation();
              setResolving(d);
              setResolutionType("release");
              setNote("");
            }}
            className="px-3 py-1.5 rounded-lg bg-[var(--primary)] text-white text-xs font-medium hover:bg-[#5A0E25] transition-colors"
          >
            Resolve
          </button>
        ) : null,
    },
  ];

  return (
    <>
      <div className="flex gap-1 mb-4 flex-wrap">
        {TABS.map((t) => {
          const count = t.key === "all" ? disputes.length : disputes.filter((d) => d.status === t.key).length;
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
        emptyTitle="No disputes here"
        emptyDescription="Orders flagged for manual review will appear here."
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
        title={detail ? `Order ${detail.orderId.slice(0, 8)}` : ""}
      >
        {detailLoading && <p className="text-sm text-[var(--muted-foreground)]">Loading…</p>}
        {detail && !detailLoading && (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <StatusBadge status={detail.status} />
              <span className="text-sm text-[var(--muted-foreground)]">Opened {formatDateTime(detail.openedAt)}</span>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Reason</p>
              <p className="text-sm text-[var(--foreground)]">{detail.reason}</p>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Restaurant</p>
              <p className="text-sm text-[var(--foreground)]">{detail.order.vendor.businessName}</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Student</p>
                <p className="text-sm text-[var(--foreground)]">{detail.order.studentUser.name ?? detail.order.studentUser.phone ?? "—"}</p>
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Runner</p>
                <p className="text-sm text-[var(--foreground)]">{detail.order.runnerUser?.name ?? detail.order.runnerUser?.phone ?? "—"}</p>
              </div>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Items</p>
              <div className="space-y-1.5">
                {detail.order.items.map((item) => (
                  <div key={item.id} className="flex items-center justify-between text-sm">
                    <span>{item.nameSnapshot} ×{item.quantity}</span>
                    <span className="font-medium">{formatKobo(item.priceSnapshot * item.quantity)}</span>
                  </div>
                ))}
                <div className="flex items-center justify-between pt-1 border-t border-[var(--border)]">
                  <span className="text-sm font-semibold">Total</span>
                  <span className="text-base font-bold text-[var(--primary)]">{formatKobo(detail.order.totalAmount)}</span>
                </div>
              </div>
            </div>

            {(detail.order.handoffPhotoUrl || detail.reporterPhotoUrl || detail.order.deliveryProofUrl) && (
              <div className="grid grid-cols-1 gap-3">
                {detail.reporterPhotoUrl && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Photo from the student&rsquo;s report</p>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={detail.reporterPhotoUrl} alt="Student-submitted report photo" className="w-full rounded-xl border border-[var(--border)]" />
                  </div>
                )}
                {detail.order.handoffPhotoUrl && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Restaurant handoff photo</p>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={detail.order.handoffPhotoUrl} alt="Restaurant handoff photo" className="w-full rounded-xl border border-[var(--border)]" />
                  </div>
                )}
                {detail.order.deliveryProofUrl && (
                  <div>
                    <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-2">Delivery proof</p>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={detail.order.deliveryProofUrl} alt="Delivery proof" className="w-full rounded-xl border border-[var(--border)]" />
                  </div>
                )}
              </div>
            )}

            {detail.order.escrow && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Escrow</p>
                <p className="text-sm text-[var(--foreground)]">
                  {detail.order.escrow.status} • Restaurant {formatKobo(detail.order.escrow.restaurantShare)} • Runner{" "}
                  {formatKobo(detail.order.escrow.runnerShare)}
                </p>
              </div>
            )}

            {detail.resolutionType && (
              <div className="p-3 rounded-lg bg-[var(--secondary)]">
                <p className="text-xs font-semibold mb-1">Resolved as &ldquo;{detail.resolutionType}&rdquo;</p>
                {detail.resolutionNote && <p className="text-sm text-[var(--muted-foreground)]">{detail.resolutionNote}</p>}
              </div>
            )}

            {detail.status === "open" && (
              <button
                onClick={() => {
                  setResolving(detail);
                  setResolutionType("release");
                  setNote("");
                }}
                className="w-full py-2.5 rounded-lg bg-[var(--primary)] text-white font-medium hover:bg-[#5A0E25] transition-colors"
              >
                Resolve
              </button>
            )}
          </div>
        )}
      </Drawer>

      <Modal
        open={!!resolving}
        onOpenChange={(open) => !open && setResolving(null)}
        title={`Resolve order ${resolving?.orderId.slice(0, 8) ?? ""}`}
        footer={
          <button
            onClick={() => setConfirmResolve(true)}
            disabled={busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Resolving…" : "Resolve dispute"}
          </button>
        }
      >
        <div className="space-y-4">
          <div className="space-y-2">
            {RESOLUTION_OPTIONS.map((opt) => (
              <label
                key={opt.key}
                className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                  resolutionType === opt.key ? "border-[var(--primary)] bg-[var(--secondary)]" : "border-[var(--border)]"
                }`}
              >
                <input
                  type="radio"
                  name="resolutionType"
                  checked={resolutionType === opt.key}
                  onChange={() => setResolutionType(opt.key)}
                  className="mt-1"
                />
                <div>
                  <p className="text-sm font-semibold">{opt.label}</p>
                  <p className="text-xs text-[var(--muted-foreground)]">{opt.description}</p>
                </div>
              </label>
            ))}
          </div>
          <div className="space-y-1">
            <label htmlFor="resolve-note" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
              Note (optional)
            </label>
            <textarea
              id="resolve-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={3}
              className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            />
          </div>
        </div>
      </Modal>

      <ConfirmDialog
        open={confirmResolve}
        onOpenChange={setConfirmResolve}
        title={`Resolve as "${resolutionType}"?`}
        description={
          resolutionType === "release"
            ? "This pays out the restaurant and runner in full via their existing payout accounts."
            : resolutionType === "refund"
              ? "This credits the student's wallet in full. Only possible while escrow is still held."
              : "This closes the dispute with no money movement."
        }
        confirmLabel={busy ? "Resolving…" : "Confirm"}
        onConfirm={resolve}
      />
    </>
  );
}
