"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Drawer, Modal } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime, formatKobo } from "@/lib/format";
import { toast } from "@/lib/toast";
import { AccountType, AdminApiError, AdminUserDetail, AdminUsersResponse, AdminUserSummary, adminClient } from "@/lib/api/admin-client";

const ROLE_TABS: { key: AccountType | "all"; label: string }[] = [
  { key: "all", label: "All" },
  { key: "student", label: "Student" },
  { key: "runner", label: "Runner" },
  { key: "restaurant", label: "Restaurant" },
  { key: "admin", label: "Admin" },
];

export function UsersBoard({ initialData }: { initialData: AdminUsersResponse }) {
  const [users, setUsers] = useState<AdminUserSummary[]>(initialData.items);
  const [filter, setFilter] = useState<AccountType | "all">("all");
  const [search, setSearch] = useState("");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<AdminUserDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [suspendTarget, setSuspendTarget] = useState<AdminUserSummary | null>(null);
  const [reason, setReason] = useState("");
  const [confirmReinstate, setConfirmReinstate] = useState<AdminUserSummary | AdminUserDetail | null>(null);
  const [busy, setBusy] = useState(false);

  async function refresh() {
    const res = await adminClient.listUsers();
    setUsers(res.items);
  }

  async function openDetail(user: AdminUserSummary) {
    setSelectedId(user.id);
    setDetailLoading(true);
    try {
      setDetail(await adminClient.getUser(user.id));
    } catch {
      toast.error("Couldn't load user details. Please try again.");
      setSelectedId(null);
    } finally {
      setDetailLoading(false);
    }
  }

  async function suspend() {
    if (!suspendTarget || !reason.trim()) return;
    setBusy(true);
    try {
      await adminClient.suspendUser(suspendTarget.id, reason.trim());
      await refresh();
      if (selectedId === suspendTarget.id) setDetail(await adminClient.getUser(suspendTarget.id));
      toast.success(`${suspendTarget.name ?? suspendTarget.email ?? "User"} suspended`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't suspend this user. Please try again.");
    } finally {
      setBusy(false);
      setSuspendTarget(null);
      setReason("");
    }
  }

  async function reinstate(user: AdminUserSummary | AdminUserDetail) {
    setBusy(true);
    try {
      await adminClient.reinstateUser(user.id);
      await refresh();
      if (selectedId === user.id) setDetail(await adminClient.getUser(user.id));
      toast.success(`${user.name ?? user.email ?? "User"} reinstated`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't reinstate this user. Please try again.");
    } finally {
      setBusy(false);
      setConfirmReinstate(null);
    }
  }

  const filtered = users
    .filter((u) => filter === "all" || u.accountType === filter)
    .filter((u) => {
      if (!search.trim()) return true;
      const q = search.trim().toLowerCase();
      return (u.name ?? "").toLowerCase().includes(q) || (u.email ?? "").toLowerCase().includes(q) || (u.phone ?? "").includes(q);
    });

  const columns: Column<AdminUserSummary>[] = [
    { key: "name", header: "Name", render: (u) => <span className="font-medium">{u.name ?? "—"}</span> },
    { key: "contact", header: "Contact", render: (u) => <span className="text-sm">{u.email ?? u.phone ?? "—"}</span> },
    { key: "accountType", header: "Role", render: (u) => <StatusBadge status={u.accountType} /> },
    { key: "createdAt", header: "Joined", sortable: true, render: (u) => formatDateTime(u.createdAt) },
    { key: "status", header: "Status", render: (u) => <StatusBadge status={u.suspendedAt ? "suspended" : "active"} /> },
    {
      key: "action",
      header: "",
      render: (u) => (
        <div onClick={(e) => e.stopPropagation()}>
          {u.suspendedAt ? (
            <button
              onClick={() => setConfirmReinstate(u)}
              className="px-3 py-1.5 rounded-lg border border-[var(--border)] text-xs font-medium hover:bg-[var(--muted)] transition-colors"
            >
              Reinstate
            </button>
          ) : (
            <button
              onClick={() => {
                setSuspendTarget(u);
                setReason("");
              }}
              className="px-3 py-1.5 rounded-lg border border-red-200 text-red-600 text-xs font-medium hover:bg-red-50 transition-colors"
            >
              Suspend
            </button>
          )}
        </div>
      ),
    },
  ];

  return (
    <>
      <div className="flex items-center gap-3 mb-4 flex-wrap">
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search name, email, or phone…"
          className="px-3 py-2 rounded-lg border border-[var(--border)] text-sm bg-card focus:outline-none focus:ring-2 focus:ring-[var(--primary)] flex-1 min-w-[200px]"
        />
        <div className="flex gap-1 flex-wrap">
          {ROLE_TABS.map((t) => (
            <button
              key={t.key}
              onClick={() => setFilter(t.key)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                filter === t.key ? "bg-[var(--primary)] text-white" : "bg-card border border-[var(--border)] text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <DataTable columns={columns} data={filtered} emptyTitle="No users found" emptyDescription="Try a different search or filter." onRowClick={openDetail} />

      <Drawer
        open={!!selectedId}
        onOpenChange={(open) => {
          if (!open) {
            setSelectedId(null);
            setDetail(null);
          }
        }}
        title={detail?.name ?? detail?.email ?? ""}
      >
        {detailLoading && <p className="text-sm text-[var(--muted-foreground)]">Loading…</p>}
        {detail && !detailLoading && (
          <div className="space-y-5">
            <div className="flex items-center gap-3">
              <StatusBadge status={detail.accountType} />
              <StatusBadge status={detail.suspendedAt ? "suspended" : "active"} />
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Contact</p>
              <p className="text-sm text-[var(--foreground)]">{detail.email ?? "—"}</p>
              <p className="text-sm text-[var(--muted-foreground)]">{detail.phone ?? "—"}</p>
            </div>

            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Joined</p>
              <p className="text-sm text-[var(--foreground)]">{formatDateTime(detail.createdAt)}</p>
            </div>

            {detail.vendor && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Vendor</p>
                <p className="text-sm text-[var(--foreground)]">{detail.vendor.businessName}</p>
                <StatusBadge status={detail.vendor.status} size="sm" />
              </div>
            )}

            {detail.wallet && (
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)] mb-1">Wallet balance</p>
                <p className="text-sm text-[var(--foreground)]">{formatKobo(detail.wallet.balance)}</p>
              </div>
            )}

            <div className="pt-2">
              {detail.suspendedAt ? (
                <button
                  onClick={() => setConfirmReinstate(detail)}
                  className="w-full py-2.5 rounded-lg border border-[var(--border)] font-medium hover:bg-[var(--muted)] transition-colors"
                >
                  Reinstate
                </button>
              ) : (
                <button
                  onClick={() => {
                    setSuspendTarget(detail);
                    setReason("");
                  }}
                  className="w-full py-2.5 rounded-lg border border-red-200 text-red-600 font-medium hover:bg-red-50 transition-colors"
                >
                  Suspend
                </button>
              )}
            </div>
          </div>
        )}
      </Drawer>

      <Modal
        open={!!suspendTarget}
        onOpenChange={(open) => {
          if (!open) {
            setSuspendTarget(null);
            setReason("");
          }
        }}
        title={`Suspend ${suspendTarget?.name ?? suspendTarget?.email ?? ""}`}
        footer={
          <button
            onClick={suspend}
            disabled={!reason.trim() || busy}
            className="px-4 py-2 rounded-lg bg-red-600 text-white text-sm font-medium hover:bg-red-700 transition-colors disabled:opacity-50"
          >
            {busy ? "Suspending…" : "Suspend user"}
          </button>
        }
      >
        <div className="space-y-2">
          <label htmlFor="suspend-reason" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
            Reason
          </label>
          <textarea
            id="suspend-reason"
            value={reason}
            onChange={(e) => setReason(e.target.value)}
            rows={3}
            className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            placeholder="e.g. Repeated policy violations"
          />
          {suspendTarget?.accountType === "restaurant" && (
            <p className="text-xs text-[var(--muted-foreground)]">This restaurant&apos;s listing will also be hidden from students.</p>
          )}
        </div>
      </Modal>

      <ConfirmDialog
        open={!!confirmReinstate}
        onOpenChange={(open) => !open && setConfirmReinstate(null)}
        title="Reinstate this user?"
        description="They will be able to log in again. A suspended vendor listing is not automatically re-approved — that goes through Vendor Review."
        confirmLabel={busy ? "Reinstating…" : "Reinstate"}
        onConfirm={() => confirmReinstate && reinstate(confirmReinstate)}
      />
    </>
  );
}
