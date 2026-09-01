"use client";

import { ReactNode, useState } from "react";
import { PageHeader } from "@/components/layout/page-header";
import { BtnPrimary, BtnSecondary } from "@/components/shared/buttons";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { Column, DataTable } from "@/components/shared/data-table";
import { Drawer, Modal } from "@/components/shared/modal";
import { EmptyState } from "@/components/shared/empty-state";
import { SkeletonBlock } from "@/components/shared/skeleton-block";
import { StatCard } from "@/components/shared/stat-card";
import { StatusBadge } from "@/components/shared/status-badge";
import { toast } from "@/lib/toast";

interface SampleRow {
  id: string;
  name: string;
  role: string;
  status: string;
  orders: number;
  joined: string;
}

// Illustrative demo data for this showcase page only — not real backend
// records. Every other page in this app either shows real data or an
// honest loading/empty state; this page is the one deliberate exception,
// clearly scoped to demonstrating the component set.
const SAMPLE_DATA: SampleRow[] = [
  { id: "1", name: "Kofi Mensah", role: "student", status: "active", orders: 47, joined: "Jan 2026" },
  { id: "2", name: "Ebo Quartey", role: "runner", status: "active", orders: 284, joined: "Mar 2026" },
  { id: "3", name: "Ji-Yeon Park", role: "restaurant", status: "active", orders: 0, joined: "Dec 2025" },
  { id: "4", name: "Lucas Bauer", role: "student", status: "suspended", orders: 12, joined: "Jan 2026" },
  { id: "5", name: "Nana Akua", role: "runner", status: "active", orders: 267, joined: "Apr 2026" },
];

const COLUMNS: Column<SampleRow>[] = [
  { key: "name", header: "Name", sortable: true },
  { key: "role", header: "Role", render: (r) => <StatusBadge status={r.role} /> },
  { key: "status", header: "Status", render: (r) => <StatusBadge status={r.status} /> },
  { key: "orders", header: "Orders", sortable: true },
  { key: "joined", header: "Joined" },
];

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="mb-10">
      <h2 className="font-fraunces text-lg font-semibold text-[var(--foreground)] mb-4 pb-2 border-b border-[var(--border)]">{title}</h2>
      {children}
    </div>
  );
}

export default function ComponentLibraryPage() {
  const [modalOpen, setModalOpen] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);

  return (
    <>
      <PageHeader title="Component Library" subtitle="Design system showcase — every shared component in one place." />

      <Section title="Typography">
        <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-6 space-y-4">
          <div>
            <p className="text-xs text-[var(--muted-foreground)] mb-1">Fraunces — Page header</p>
            <h1 className="font-fraunces text-3xl font-semibold text-[var(--foreground)]">RUN-It Campus Delivery</h1>
          </div>
          <div>
            <p className="text-xs text-[var(--muted-foreground)] mb-1">Inter — Body text</p>
            <p className="text-base text-[var(--foreground)] leading-relaxed max-w-prose">
              Authentic West African and Caribbean cuisine made fresh daily. Our platform connects students with the best campus
              vendors, delivered hot and on time.
            </p>
          </div>
          <div>
            <p className="text-xs text-[var(--muted-foreground)] mb-1">Inter Semibold — Label / Caption</p>
            <p className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)]">Status · Updated 2m ago · 124 active runners</p>
          </div>
        </div>
      </Section>

      <Section title="Brand palette">
        <div className="flex flex-wrap gap-3">
          {[
            { name: "Burgundy", color: "#7A1636" },
            { name: "Dark Burgundy", color: "#5A0E25" },
            { name: "Gold", color: "#D99A18" },
            { name: "Background", color: "#F4F2EE" },
            { name: "Card", color: "#FFFFFF" },
            { name: "Secondary", color: "#EDE8E1" },
            { name: "Muted", color: "#E4DDD5" },
          ].map((c) => (
            <div key={c.name} className="flex items-center gap-2">
              <div className="w-10 h-10 rounded-lg shadow-sm border border-[var(--border)]" style={{ background: c.color }} />
              <div>
                <p className="text-xs font-medium text-[var(--foreground)]">{c.name}</p>
                <p className="text-[10px] text-[var(--muted-foreground)] font-mono">{c.color}</p>
              </div>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Buttons">
        <div className="flex flex-wrap gap-3 items-center">
          <BtnPrimary onClick={() => toast.success("Primary button clicked")}>Primary action</BtnPrimary>
          <BtnSecondary onClick={() => toast.info("Secondary button clicked")}>Secondary action</BtnSecondary>
          <button className="px-4 py-2 rounded-lg text-sm font-medium text-red-500 bg-red-50 hover:bg-red-100 border border-red-200 transition-colors">
            Destructive
          </button>
          <BtnPrimary disabled>Disabled</BtnPrimary>
        </div>
      </Section>

      <Section title="Status badges">
        <div className="flex flex-wrap gap-2">
          {["new", "preparing", "ready", "completed", "cancelled", "pending", "approved", "rejected", "open", "resolved", "refunded", "active", "suspended", "student", "runner", "restaurant", "admin", "processing"].map(
            (s) => (
              <StatusBadge key={s} status={s} />
            ),
          )}
        </div>
      </Section>

      <Section title="StatCard">
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            icon={
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <circle cx="9" cy="9" r="7" stroke="currentColor" strokeWidth="1.5" />
                <path d="M9 5v4l2.5 2.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
            }
            label="Platform GMV"
            value="₦ 284,940"
            trend={{ value: 15, label: "vs. last month" }}
            accent="burgundy"
          />
          <StatCard
            icon={
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M3 3h12M3 3l1.5 10H13.5L15 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            }
            label="Total orders"
            value="3,540"
            trend={{ value: -2, label: "vs. last month" }}
            accent="gold"
          />
          <StatCard
            icon={
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M2 14L6 9l3 3 3-4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            }
            label="Avg. order value"
            value="₦ 89.35"
            accent="green"
          />
          <StatCard
            icon={
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
                <path d="M8 1L9.5 5.5 15 6l-4 3.5 1.5 5.5L8 12l-4.5 3 1.5-5.5L1 6l5.5-.5L8 1z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
              </svg>
            }
            label="Active vendors"
            value="38"
            accent="blue"
          />
        </div>
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
          <StatCard icon={<span />} label="Loading state" value="" loading />
          <StatCard icon={<span />} label="Loading state" value="" loading />
        </div>
      </Section>

      <Section title="DataTable">
        <DataTable columns={COLUMNS} data={SAMPLE_DATA} pageSize={3} onRowClick={() => toast.info("Row clicked")} />
        <div className="mt-4">
          <h4 className="text-xs font-semibold text-[var(--muted-foreground)] mb-2">Empty state</h4>
          <DataTable columns={COLUMNS} data={[]} emptyTitle="No users found" emptyDescription="Try adjusting your search or filters." />
        </div>
        <div className="mt-4">
          <h4 className="text-xs font-semibold text-[var(--muted-foreground)] mb-2">Loading state</h4>
          <DataTable columns={COLUMNS} data={[]} loading />
        </div>
      </Section>

      <Section title="Skeleton blocks">
        <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-6 space-y-3 max-w-sm">
          <SkeletonBlock className="h-4" width="70%" />
          <SkeletonBlock className="h-4" width="90%" />
          <SkeletonBlock className="h-4" width="50%" />
        </div>
      </Section>

      <Section title="Toast notifications">
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => toast.success("Order #A-1042 marked as ready for pickup.")}
            className="px-3 py-2 rounded-lg bg-emerald-600 text-white text-sm font-medium hover:bg-emerald-700 transition-colors"
          >
            Success toast
          </button>
          <button
            onClick={() => toast.error("Failed to update item. Please try again.")}
            className="px-3 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors"
          >
            Error toast
          </button>
          <button
            onClick={() => toast.info("Vendor application sent for review.")}
            className="px-3 py-2 rounded-lg bg-slate-700 text-white text-sm font-medium hover:bg-slate-800 transition-colors"
          >
            Info toast
          </button>
        </div>
      </Section>

      <Section title="Modal, Drawer &amp; Confirm dialog">
        <div className="flex flex-wrap gap-3">
          <BtnSecondary onClick={() => setModalOpen(true)}>Open modal</BtnSecondary>
          <BtnSecondary onClick={() => setDrawerOpen(true)}>Open drawer</BtnSecondary>
          <button
            onClick={() => setConfirmOpen(true)}
            className="px-4 py-2 rounded-lg text-sm font-medium text-red-500 bg-red-50 hover:bg-red-100 border border-red-200 transition-colors"
          >
            Confirm dialog (destructive)
          </button>
        </div>
      </Section>

      <Section title="Empty state">
        <EmptyState
          title="No orders yet"
          description="When your first order comes in, it will appear here. Make sure your menu is live and your restaurant is marked as open."
          action={<BtnPrimary>View menu settings</BtnPrimary>}
        />
      </Section>

      <Modal
        open={modalOpen}
        onOpenChange={setModalOpen}
        title="Example modal"
        footer={
          <>
            <BtnSecondary onClick={() => setModalOpen(false)}>Cancel</BtnSecondary>
            <BtnPrimary
              onClick={() => {
                setModalOpen(false);
                toast.success("Changes saved");
              }}
            >
              Save changes
            </BtnPrimary>
          </>
        }
      >
        <div className="space-y-4">
          <div>
            <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">Name</label>
            <input
              type="text"
              placeholder="e.g. Spice Garden"
              className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">Description</label>
            <textarea rows={3} className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm resize-none focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]" />
          </div>
        </div>
      </Modal>

      <Drawer open={drawerOpen} onOpenChange={setDrawerOpen} title="Example drawer" description="Drawers are a thin wrapper over shadcn's Sheet.">
        <p className="text-sm text-[var(--muted-foreground)]">Useful for detail panels — an order&apos;s full item list, a dispute&apos;s timeline, a vendor application&apos;s documents.</p>
      </Drawer>

      <ConfirmDialog
        open={confirmOpen}
        onOpenChange={setConfirmOpen}
        title="Delete this item?"
        description="This action cannot be undone. The item will be permanently removed from the menu."
        confirmLabel="Delete item"
        destructive
        onConfirm={() => {
          setConfirmOpen(false);
          toast.info("Item deleted");
        }}
      />
    </>
  );
}
