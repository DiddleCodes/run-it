"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { Drawer, Modal } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime } from "@/lib/format";
import { toast } from "@/lib/toast";
import {
  AdminApiError,
  AdminRunnerKycDetail,
  AdminRunnerKycResponse,
  AdminRunnerKycSummary,
  RunnerKycReviewStatus,
  adminClient,
} from "@/lib/api/admin-client";

const TABS: { key: RunnerKycReviewStatus | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "pending", label: "Pending" },
  { key: "approved", label: "Approved" },
  { key: "rejected", label: "Rejected" },
];

const RUNNER_TYPE_LABEL: Record<string, string> = {
  student_runner: "Student runner",
  independent_rider: "Independent rider",
};

const VEHICLE_TYPE_LABEL: Record<string, string> = {
  bicycle: "Bicycle",
  motorbike: "Motorbike",
  keke: "Keke",
};

// Task 29: mirrors VendorReviewBoard's structure directly — same
// tabs/table/drawer/approve-reject-modal shape, reviewing RunnerKyc
// submissions (three real photos + declared vehicle) instead of vendor
// applications. No campus picker here — a runner's campus is a separate
// admin action, unrelated to identity verification.
export function RunnerKycReviewBoard({ initialData }: { initialData: AdminRunnerKycResponse }) {
  const [submissions, setSubmissions] = useState<AdminRunnerKycSummary[]>(initialData.items);
  const [filter, setFilter] = useState<RunnerKycReviewStatus | "all">("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminRunnerKycDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [approveTarget, setApproveTarget] = useState<AdminRunnerKycSummary | null>(null);
  const [rejectTarget, setRejectTarget] = useState<AdminRunnerKycSummary | null>(null);
  const [rejectReason, setRejectReason] = useState("");
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const res = await adminClient.listRunnerKyc();
    setSubmissions(res.items);
  }

  async function openDetail(kyc: AdminRunnerKycSummary) {
    setSelectedId(kyc.id);
    setDetailLoading(true);
    try {
      setDetail(await adminClient.getRunnerKyc(kyc.id));
    } catch {
      toast.error("Couldn't load this submission. Please try again.");
      setSelectedId(null);
    } finally {
      setDetailLoading(false);
    }
  }

  async function approve(kyc: AdminRunnerKycSummary) {
    setBusy(true);
    try {
      await adminClient.approveRunnerKyc(kyc.id);
      await refresh();
      if (selectedId === kyc.id) setDetail(await adminClient.getRunnerKyc(kyc.id));
      toast.success(`${kyc.user.name ?? "Runner"} approved`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't approve this runner. Please try again.");
    } finally {
      setBusy(false);
      setApproveTarget(null);
    }
  }

  async function reject() {
    if (!rejectTarget || !rejectReason.trim()) return;
    setBusy(true);
    try {
      await adminClient.rejectRunnerKyc(rejectTarget.id, rejectReason.trim());
      await refresh();
      if (selectedId === rejectTarget.id) setDetail(await adminClient.getRunnerKyc(rejectTarget.id));
      toast.success(`${rejectTarget.user.name ?? "Runner"} rejected`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't reject this runner. Please try again.");
    } finally {
      setBusy(false);
      setRejectTarget(null);
      setRejectReason("");
    }
  }

  const filtered = filter === "all" ? submissions : submissions.filter((k) => k.status === filter);

  const columns: Column<AdminRunnerKycSummary>[] = [
    { key: "user", header: "Runner", render: (k) => <span className="font-medium">{k.user.name ?? k.user.email ?? "—"}</span> },
    { key: "runnerType", header: "Type", render: (k) => (k.runnerType ? RUNNER_TYPE_LABEL[k.runnerType] : "—") },
    { key: "vehicleType", header: "Vehicle", render: (k) => (k.vehicleType ? VEHICLE_TYPE_LABEL[k.vehicleType] : "—") },
    { key: "submittedAt", header: "Submitted", sortable: true, render: (k) => formatDateTime(k.submittedAt) },
    { key: "status", header: "Status", render: (k) => <StatusBadge status={k.status} /> },
    {
      key: "action",
      header: "",
      render: (k) =>
        k.status === "pending" ? (
          <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
            <button
              onClick={() => setApproveTarget(k)}
              className="px-3 py-1.5 rounded-lg bg-[var(--primary)] text-white text-xs font-medium hover:bg-[#5A0E25] transition-colors"
            >
              Approve
            </button>
            <button
              onClick={() => setRejectTarget(k)}
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
          const count = t.key === "all" ? submissions.length : submissions.filter((k) => k.status === t.key).length;
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
        emptyTitle="No runner KYC submissions here"
        emptyDescription="Runner identity/vehicle submissions will appear here for review."
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
        title={detail?.user.name ?? "Runner KYC"}
      >
        {detailLoading && <p className="text-sm text-[var(--muted-foreground)]">Loading…</p>}
        {detail && !detailLoading && (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <StatusBadge status={detail.status} />
              <span className="text-sm text-[var(--muted-foreground)]">Submitted {formatDateTime(detail.submittedAt)}</span>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Runner</p>
              <p className="text-sm text-[var(--foreground)]">{detail.user.name ?? "—"}</p>
              <p className="text-sm text-[var(--muted-foreground)]">{detail.user.email}</p>
              <p className="text-sm text-[var(--muted-foreground)]">{detail.user.phone}</p>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Runner type</p>
              <p className="text-sm text-[var(--foreground)]">{detail.runnerType ? RUNNER_TYPE_LABEL[detail.runnerType] : "—"}</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">
                  {detail.idType === "government_id" ? "Government ID" : "Student ID"}
                </p>
                {detail.idPhotoUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={detail.idPhotoUrl} alt="ID" className="w-full h-32 object-cover rounded-lg border border-[var(--border)]" />
                ) : (
                  <p className="text-sm text-[var(--muted-foreground)]">Not submitted</p>
                )}
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Selfie</p>
                {detail.selfiePhotoUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={detail.selfiePhotoUrl} alt="Selfie" className="w-full h-32 object-cover rounded-lg border border-[var(--border)]" />
                ) : (
                  <p className="text-sm text-[var(--muted-foreground)]">Not submitted</p>
                )}
              </div>
            </div>

            {detail.vehiclePhotoUrl && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">
                  Vehicle — {detail.vehicleType ? VEHICLE_TYPE_LABEL[detail.vehicleType] : "—"}
                  {detail.vehiclePlate ? ` · ${detail.vehiclePlate}` : ""}
                </p>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={detail.vehiclePhotoUrl} alt="Vehicle" className="w-full h-40 object-cover rounded-lg border border-[var(--border)]" />
              </div>
            )}

            {detail.rejectionReason && (
              <div className="p-3 rounded-lg bg-red-50 border border-red-200">
                <p className="text-xs font-semibold text-red-700 mb-1">Rejection reason</p>
                <p className="text-sm text-red-700">{detail.rejectionReason}</p>
              </div>
            )}

            {detail.status === "pending" && (
              <div className="flex gap-2">
                <button
                  onClick={() => setApproveTarget(detail)}
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

      <Modal
        open={!!approveTarget}
        onOpenChange={(open) => !open && setApproveTarget(null)}
        title={`Approve ${approveTarget?.user.name ?? "runner"}`}
        footer={
          <button
            onClick={() => approveTarget && approve(approveTarget)}
            disabled={busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Approving…" : "Approve"}
          </button>
        }
      >
        <p className="text-sm text-[var(--muted-foreground)]">
          {approveTarget?.user.name ?? "This runner"} will be able to claim and deliver real orders immediately.
        </p>
      </Modal>

      <Modal
        open={!!rejectTarget}
        onOpenChange={(open) => {
          if (!open) {
            setRejectTarget(null);
            setRejectReason("");
          }
        }}
        title={`Reject ${rejectTarget?.user.name ?? "runner"}`}
        footer={
          <button
            onClick={reject}
            disabled={!rejectReason.trim() || busy}
            className="px-4 py-2 rounded-lg bg-red-600 text-white text-sm font-medium hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {busy ? "Rejecting…" : "Reject submission"}
          </button>
        }
      >
        <div className="space-y-2">
          <label htmlFor="reject-kyc-reason" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
            Reason (shown to the runner)
          </label>
          <textarea
            id="reject-kyc-reason"
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
            rows={4}
            className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            placeholder="e.g. ID photo was blurry — please retake in better lighting"
          />
        </div>
      </Modal>
    </>
  );
}
