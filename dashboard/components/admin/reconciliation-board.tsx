"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { EmptyState } from "@/components/shared/empty-state";
import { Modal } from "@/components/shared/modal";
import { formatDateTime, formatKobo } from "@/lib/format";
import { toast } from "@/lib/toast";
import {
  AdminApiError,
  ReconciliationMismatch,
  ReconciliationReport,
  ReconciliationRun,
  adminClient,
} from "@/lib/api/admin-client";

const RANGES = [
  { label: "Last 7 days", days: 7 },
  { label: "Last 30 days", days: 30 },
  { label: "Last 90 days", days: 90 },
];

const KIND_LABEL: Record<string, string> = {
  missing_locally: "Missing locally",
  missing_on_paystack: "Missing on Paystack",
  amount_mismatch: "Amount mismatch",
  status_mismatch: "Status mismatch",
};

function SummaryCard({ label, value }: { label: string; value: number }) {
  return (
    <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-4">
      <p className="text-2xl font-bold text-[var(--foreground)]">{value}</p>
      <p className="text-xs text-[var(--muted-foreground)] mt-1">{label}</p>
    </div>
  );
}

export function ReconciliationBoard({
  initialData,
  initialHistory,
}: {
  initialData: ReconciliationReport | null;
  initialHistory: ReconciliationRun[];
}) {
  // Unlike every other admin board, the report depends on a live Paystack
  // call — null means that call failed (Paystack unreachable/misconfigured),
  // not "no data yet". Shown as a real error state with retry, not silently
  // treated as an empty report.
  const [report, setReport] = useState<ReconciliationReport | null>(initialData);
  const [reportError, setReportError] = useState(initialData === null);
  const [history, setHistory] = useState<ReconciliationRun[]>(initialHistory);
  const [rangeDays, setRangeDays] = useState(30);
  const [loading, setLoading] = useState(false);
  const [resolving, setResolving] = useState<ReconciliationMismatch | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);

  async function loadReport(days: number) {
    setLoading(true);
    try {
      const to = new Date();
      const from = new Date(to.getTime() - days * 24 * 60 * 60 * 1000);
      setReport(await adminClient.getReconciliationReport({ from: from.toISOString(), to: to.toISOString() }));
      setReportError(false);
    } catch (err) {
      setReportError(true);
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't reach Paystack. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  async function selectRange(days: number) {
    setRangeDays(days);
    await loadReport(days);
  }

  async function resolve() {
    if (!resolving || !note.trim()) return;
    setBusy(true);
    try {
      await adminClient.resolveMismatch(resolving.reference, note.trim());
      await loadReport(rangeDays);
      toast.success(`${resolving.reference} marked resolved`);
      setResolving(null);
      setNote("");
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't mark this resolved. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function refreshHistory() {
    setHistory(await adminClient.getReconciliationHistory());
  }

  // DataTable requires an `id` field; a reference is a unique enough key here.
  const rows = (report?.mismatches ?? []).map((m) => ({ ...m, id: m.reference }));

  const historyColumns: Column<ReconciliationRun>[] = [
    { key: "startedAt", header: "Started", render: (run) => formatDateTime(run.startedAt) },
    { key: "walletChecked", header: "Wallet checked", className: "text-right", render: (run) => <span>{run.walletChecked}</span> },
    { key: "transferLegsChecked", header: "Transfer legs checked", className: "text-right", render: (run) => <span>{run.transferLegsChecked}</span> },
    { key: "mismatchCount", header: "Mismatches", className: "text-right", render: (run) => <span>{run.mismatchCount}</span> },
    {
      key: "triggeredBy",
      header: "Triggered by",
      render: (run) => <span className="text-[var(--muted-foreground)]">{run.triggeredBy ? "Admin" : "Scheduled sweep"}</span>,
    },
  ];

  const columns: Column<ReconciliationMismatch & { id: string }>[] = [
    { key: "reference", header: "Reference", render: (m) => <span className="font-mono text-xs">{m.reference}</span> },
    { key: "type", header: "Type", render: (m) => (m.type === "wallet_topup" ? "Wallet top-up" : "Transfer") },
    { key: "kind", header: "Issue", render: (m) => <span className="text-sm">{KIND_LABEL[m.kind] ?? m.kind}</span> },
    { key: "localAmount", header: "Local", render: (m) => (m.localAmount != null ? formatKobo(m.localAmount) : "—") },
    { key: "paystackAmount", header: "Paystack", render: (m) => (m.paystackAmount != null ? formatKobo(m.paystackAmount) : "—") },
    {
      key: "resolved",
      header: "Status",
      render: (m) =>
        m.resolved ? (
          <span className="text-xs px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">Resolved</span>
        ) : (
          <button
            onClick={(e) => {
              e.stopPropagation();
              setResolving(m);
              setNote("");
            }}
            className="px-3 py-1.5 rounded-lg bg-[var(--primary)] text-white text-xs font-medium hover:bg-[#5A0E25] transition-colors"
          >
            Mark resolved
          </button>
        ),
    },
  ];

  return (
    <>
      <div className="flex items-center justify-end mb-6">
        <div className="flex rounded-lg border border-[var(--border)] overflow-hidden bg-card">
          {RANGES.map((r) => (
            <button
              key={r.days}
              onClick={() => selectRange(r.days)}
              className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                r.days === rangeDays ? "bg-[var(--primary)] text-white" : "text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {r.label}
            </button>
          ))}
        </div>
      </div>

      {reportError ? (
        <EmptyState
          title="Couldn't reach Paystack"
          description="The comparison report needs a live call to Paystack's transaction/transfer APIs. That call failed — check the Paystack credentials and try again."
          action={
            <button
              onClick={() => loadReport(rangeDays)}
              className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors"
            >
              {loading ? "Retrying…" : "Retry"}
            </button>
          }
        />
      ) : (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-6">
            <SummaryCard label="Matched" value={report?.summary.matched ?? 0} />
            <SummaryCard label="Missing locally" value={report?.summary.missingLocally ?? 0} />
            <SummaryCard label="Missing on Paystack" value={report?.summary.missingOnPaystack ?? 0} />
            <SummaryCard label="Amount mismatch" value={report?.summary.amountMismatch ?? 0} />
            <SummaryCard label="Status mismatch" value={report?.summary.statusMismatch ?? 0} />
          </div>

          <DataTable
            columns={columns}
            data={rows}
            loading={loading}
            emptyTitle="No mismatches"
            emptyDescription="Everything in this range matches Paystack's records."
          />
        </>
      )}

      <div className="flex items-center justify-between mt-6 mb-3">
        <h3 className="font-semibold text-[var(--foreground)]">Reconciliation run history</h3>
        <button onClick={refreshHistory} className="text-xs text-[var(--muted-foreground)] hover:text-[var(--foreground)]">
          Refresh
        </button>
      </div>
      <DataTable
        columns={historyColumns}
        data={history}
        emptyTitle="No reconciliation runs logged yet"
        emptyDescription="Runs appear here after the scheduled sweep or a manual trigger."
      />

      <Modal
        open={!!resolving}
        onOpenChange={(open) => !open && setResolving(null)}
        title={`Mark ${resolving?.reference ?? ""} resolved`}
        footer={
          <button
            onClick={resolve}
            disabled={!note.trim() || busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Saving…" : "Mark resolved"}
          </button>
        }
      >
        <div className="space-y-2">
          <label htmlFor="resolve-mismatch-note" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
            Note (required)
          </label>
          <textarea
            id="resolve-mismatch-note"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            rows={3}
            className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            placeholder="e.g. Confirmed manually against Paystack dashboard — indexing delay"
          />
        </div>
      </Modal>
    </>
  );
}
