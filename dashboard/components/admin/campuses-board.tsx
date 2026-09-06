"use client";

import { useState } from "react";
import { Column, DataTable } from "@/components/shared/data-table";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Modal } from "@/components/shared/modal";
import { StatusBadge } from "@/components/shared/status-badge";
import { formatDateTime } from "@/lib/format";
import { toast } from "@/lib/toast";
import { AdminApiError, AdminCampusDetail, adminClient } from "@/lib/api/admin-client";

function domainsToText(domains: string[]) {
  return domains.join(", ");
}

function textToDomains(text: string) {
  return text
    .split(",")
    .map((d) => d.trim())
    .filter((d) => d.length > 0);
}

export function CampusesBoard({ initialData }: { initialData: AdminCampusDetail[] }) {
  const [campuses, setCampuses] = useState<AdminCampusDetail[]>(initialData);
  const [addOpen, setAddOpen] = useState(false);
  const [editTarget, setEditTarget] = useState<AdminCampusDetail | null>(null);
  const [name, setName] = useState("");
  const [domainsText, setDomainsText] = useState("");
  const [busy, setBusy] = useState(false);
  const [deactivateTarget, setDeactivateTarget] = useState<AdminCampusDetail | null>(null);
  const [deleteTarget, setDeleteTarget] = useState<AdminCampusDetail | null>(null);

  async function refresh() {
    setCampuses(await adminClient.listAdminCampuses());
  }

  function openAdd() {
    setName("");
    setDomainsText("");
    setAddOpen(true);
  }

  function openEdit(campus: AdminCampusDetail) {
    setName(campus.name);
    setDomainsText(domainsToText(campus.allowedEmailDomains));
    setEditTarget(campus);
  }

  async function submitAdd() {
    const domains = textToDomains(domainsText);
    if (!name.trim() || domains.length === 0) return;
    setBusy(true);
    try {
      await adminClient.createCampus(name.trim(), domains);
      await refresh();
      toast.success(`${name.trim()} added`);
      setAddOpen(false);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't create this campus. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function submitEdit() {
    if (!editTarget) return;
    const domains = textToDomains(domainsText);
    if (!name.trim() || domains.length === 0) return;
    setBusy(true);
    try {
      await adminClient.updateCampus(editTarget.id, { name: name.trim(), allowedEmailDomains: domains });
      await refresh();
      toast.success(`${name.trim()} updated`);
      setEditTarget(null);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't update this campus. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function deactivate() {
    if (!deactivateTarget) return;
    setBusy(true);
    try {
      await adminClient.deactivateCampus(deactivateTarget.id);
      await refresh();
      toast.success(`${deactivateTarget.name} deactivated`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't deactivate this campus. Please try again.");
    } finally {
      setBusy(false);
      setDeactivateTarget(null);
    }
  }

  async function reactivate(campus: AdminCampusDetail) {
    setBusy(true);
    try {
      await adminClient.reactivateCampus(campus.id);
      await refresh();
      toast.success(`${campus.name} reactivated`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't reactivate this campus. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (!deleteTarget) return;
    setBusy(true);
    try {
      await adminClient.deleteCampus(deleteTarget.id);
      await refresh();
      toast.success(`${deleteTarget.name} deleted`);
    } catch (err) {
      toast.error(err instanceof AdminApiError ? err.message : "Couldn't delete this campus. Please try again.");
    } finally {
      setBusy(false);
      setDeleteTarget(null);
    }
  }

  const columns: Column<AdminCampusDetail>[] = [
    { key: "name", header: "Name", render: (c) => <span className="font-medium">{c.name}</span> },
    { key: "allowedEmailDomains", header: "Domains", render: (c) => <span className="text-sm">{domainsToText(c.allowedEmailDomains)}</span> },
    { key: "studentCount", header: "Students", sortable: true, render: (c) => <span className="text-sm">{c.studentCount}</span> },
    { key: "vendorCount", header: "Vendors", sortable: true, render: (c) => <span className="text-sm">{c.vendorCount}</span> },
    { key: "isActive", header: "Status", render: (c) => <StatusBadge status={c.isActive ? "active" : "inactive"} /> },
    { key: "createdAt", header: "Created", sortable: true, render: (c) => formatDateTime(c.createdAt) },
    {
      key: "action",
      header: "",
      render: (c) => (
        <div className="flex gap-2" onClick={(e) => e.stopPropagation()}>
          <button
            onClick={() => openEdit(c)}
            className="px-3 py-1.5 rounded-lg border border-[var(--border)] text-xs font-medium hover:bg-[var(--muted)] transition-colors"
          >
            Edit
          </button>
          {c.isActive ? (
            <button
              onClick={() => setDeactivateTarget(c)}
              className="px-3 py-1.5 rounded-lg border border-amber-200 text-amber-700 text-xs font-medium hover:bg-amber-50 transition-colors"
            >
              Deactivate
            </button>
          ) : (
            <button
              onClick={() => reactivate(c)}
              disabled={busy}
              className="px-3 py-1.5 rounded-lg border border-emerald-200 text-emerald-700 text-xs font-medium hover:bg-emerald-50 transition-colors disabled:opacity-50"
            >
              Reactivate
            </button>
          )}
          <button
            onClick={() => setDeleteTarget(c)}
            disabled={c.studentCount > 0 || c.vendorCount > 0}
            title={c.studentCount > 0 || c.vendorCount > 0 ? "Only an unused campus can be deleted — deactivate instead" : undefined}
            className="px-3 py-1.5 rounded-lg border border-red-200 text-red-600 text-xs font-medium hover:bg-red-50 transition-colors disabled:opacity-40 disabled:hover:bg-transparent"
          >
            Delete
          </button>
        </div>
      ),
    },
  ];

  return (
    <>
      <div className="flex justify-end mb-4">
        <button
          onClick={openAdd}
          className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors"
        >
          + Add campus
        </button>
      </div>

      <DataTable columns={columns} data={campuses} emptyTitle="No campuses yet" emptyDescription="Add the first one to open signups." />

      <Modal
        open={addOpen}
        onOpenChange={setAddOpen}
        title="Add campus"
        footer={
          <button
            onClick={submitAdd}
            disabled={!name.trim() || textToDomains(domainsText).length === 0 || busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Adding…" : "Add campus"}
          </button>
        }
      >
        <CampusFormFields name={name} setName={setName} domainsText={domainsText} setDomainsText={setDomainsText} />
      </Modal>

      <Modal
        open={!!editTarget}
        onOpenChange={(open) => !open && setEditTarget(null)}
        title={`Edit ${editTarget?.name ?? ""}`}
        footer={
          <button
            onClick={submitEdit}
            disabled={!name.trim() || textToDomains(domainsText).length === 0 || busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Saving…" : "Save"}
          </button>
        }
      >
        <CampusFormFields name={name} setName={setName} domainsText={domainsText} setDomainsText={setDomainsText} />
      </Modal>

      <ConfirmDialog
        open={!!deactivateTarget}
        onOpenChange={(open) => !open && setDeactivateTarget(null)}
        title={`Deactivate ${deactivateTarget?.name ?? ""}?`}
        description={`${deactivateTarget?.studentCount ?? 0} student(s) and ${deactivateTarget?.vendorCount ?? 0} vendor(s) are currently on this campus. They will be completely unaffected — this only stops new signups from matching this campus's email domains.`}
        confirmLabel={busy ? "Deactivating…" : "Deactivate"}
        onConfirm={deactivate}
      />

      <ConfirmDialog
        open={!!deleteTarget}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title={`Delete ${deleteTarget?.name ?? ""}?`}
        description="This permanently removes the campus. This can't be undone."
        confirmLabel={busy ? "Deleting…" : "Delete"}
        destructive
        onConfirm={remove}
      />
    </>
  );
}

function CampusFormFields({
  name,
  setName,
  domainsText,
  setDomainsText,
}: {
  name: string;
  setName: (v: string) => void;
  domainsText: string;
  setDomainsText: (v: string) => void;
}) {
  return (
    <div className="space-y-4">
      <div className="space-y-2">
        <label htmlFor="campus-name" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
          Name
        </label>
        <input
          id="campus-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. University of Ibadan"
          className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
        />
      </div>
      <div className="space-y-2">
        <label htmlFor="campus-domains" className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-foreground)]">
          Allowed email domains
        </label>
        <input
          id="campus-domains"
          value={domainsText}
          onChange={(e) => setDomainsText(e.target.value)}
          placeholder="student.ui.edu.ng, ui.edu.ng"
          className="w-full rounded-lg border border-[var(--border)] px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
        />
        <p className="text-xs text-[var(--muted-foreground)]">Comma-separated. A student's signup email must match one of these exactly.</p>
      </div>
    </div>
  );
}
