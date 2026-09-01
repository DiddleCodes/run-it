"use client";

import { useState } from "react";
import { BtnPrimary } from "@/components/shared/buttons";
import { ConfirmDialog } from "@/components/shared/confirm-dialog";
import { EmptyState } from "@/components/shared/empty-state";
import { formatKobo } from "@/lib/format";
import { toast } from "@/lib/toast";
import { MenuItem, VendorApiError, vendorClient } from "@/lib/api/vendor-client";
import { MenuItemFormModal } from "./menu-item-form-modal";

export function MenuBoard({ vendorId, initialItems }: { vendorId: string; initialItems: MenuItem[] }) {
  const [items, setItems] = useState<MenuItem[]>(initialItems);
  const [filterCat, setFilterCat] = useState<string>("all");
  const [editItem, setEditItem] = useState<MenuItem | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<MenuItem | null>(null);
  const [togglingId, setTogglingId] = useState<string | null>(null);

  const categories = Array.from(new Set(items.map((i) => i.category))).sort();

  async function refresh() {
    const { items } = await vendorClient.getMenu(vendorId);
    setItems(items);
  }

  async function handleToggle(item: MenuItem) {
    setTogglingId(item.id);
    try {
      await vendorClient.setAvailability(item.id, !item.isAvailable);
      await refresh();
      toast.success("Item availability updated");
    } catch (err) {
      toast.error(err instanceof VendorApiError ? err.message : "Couldn't update availability.");
    } finally {
      setTogglingId(null);
    }
  }

  async function handleSubmit(dto: { name: string; description?: string; price: number; photoUrl?: string; category: string }) {
    if (editItem) {
      await vendorClient.updateMenuItem(editItem.id, dto);
      toast.success("Item updated");
    } else {
      await vendorClient.createMenuItem(dto);
      toast.success("Item added to menu");
    }
    await refresh();
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    try {
      await vendorClient.deleteMenuItem(deleteTarget.id);
      toast.info("Item removed from menu");
      await refresh();
    } catch (err) {
      toast.error(err instanceof VendorApiError ? err.message : "Couldn't remove the item.");
    } finally {
      setDeleteTarget(null);
    }
  }

  const groups = categories.filter((c) => filterCat === "all" || filterCat === c).map((cat) => ({ cat, items: items.filter((i) => i.category === cat) }));

  return (
    <>
      <div className="flex items-center justify-between mb-5 flex-wrap gap-3">
        <div className="flex gap-2 flex-wrap">
          {["all", ...categories].map((c) => (
            <button
              key={c}
              onClick={() => setFilterCat(c)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all capitalize ${
                filterCat === c ? "bg-[var(--primary)] text-white" : "bg-card border border-[var(--border)] text-[var(--muted-foreground)] hover:text-[var(--foreground)]"
              }`}
            >
              {c === "all" ? "All categories" : c}
            </button>
          ))}
        </div>
        <BtnPrimary
          onClick={() => {
            setEditItem(null);
            setModalOpen(true);
          }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <path d="M7 1v12M1 7h12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
          </svg>
          Add item
        </BtnPrimary>
      </div>

      {items.length === 0 ? (
        <EmptyState
          title="No menu items yet"
          description="Add your first item to start receiving orders."
          action={
            <BtnPrimary
              onClick={() => {
                setEditItem(null);
                setModalOpen(true);
              }}
            >
              Add item
            </BtnPrimary>
          }
        />
      ) : (
        <div className="space-y-6">
          {groups.map(({ cat, items: catItems }) => (
            <div key={cat}>
              <h3 className="text-xs font-semibold uppercase tracking-widest text-[var(--muted-foreground)] mb-3">{cat}</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                {catItems.map((item) => (
                  <div
                    key={item.id}
                    className={`bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] overflow-hidden flex gap-3 p-3 transition-all ${
                      !item.isAvailable ? "opacity-60" : ""
                    }`}
                  >
                    <div className="w-20 h-20 rounded-lg overflow-hidden bg-[var(--secondary)] flex-shrink-0">
                      {item.photoUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={item.photoUrl} alt={item.name} className="w-full h-full object-cover" />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-2xl opacity-20">🍽</div>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-start justify-between gap-1 mb-0.5">
                        <p className="text-sm font-semibold text-[var(--foreground)] leading-tight">{item.name}</p>
                        <span className="text-sm font-bold text-[var(--primary)] flex-shrink-0">{formatKobo(item.price)}</span>
                      </div>
                      {item.description && <p className="text-xs text-[var(--muted-foreground)] line-clamp-2 mb-2">{item.description}</p>}
                      <div className="flex items-center justify-between mt-2">
                        <button
                          onClick={() => handleToggle(item)}
                          disabled={togglingId === item.id}
                          className={`flex items-center gap-1.5 text-xs font-medium transition-colors disabled:opacity-50 ${
                            item.isAvailable ? "text-emerald-600" : "text-[var(--muted-foreground)]"
                          }`}
                        >
                          <span className={`w-7 h-4 rounded-full relative transition-colors ${item.isAvailable ? "bg-emerald-500" : "bg-[var(--muted)]"}`}>
                            <span
                              className={`absolute top-0.5 w-3 h-3 rounded-full bg-white shadow-sm transition-transform ${
                                item.isAvailable ? "translate-x-3.5" : "translate-x-0.5"
                              }`}
                            />
                          </span>
                          {item.isAvailable ? "On" : "Off"}
                        </button>
                        <div className="flex gap-1">
                          <button
                            onClick={() => {
                              setEditItem(item);
                              setModalOpen(true);
                            }}
                            className="p-1.5 rounded-md hover:bg-[var(--secondary)] text-[var(--muted-foreground)] hover:text-[var(--foreground)] transition-colors"
                          >
                            <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                              <path d="M9 2l2 2-6 6H3V8l6-6z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" />
                            </svg>
                          </button>
                          <button
                            onClick={() => setDeleteTarget(item)}
                            className="p-1.5 rounded-md hover:bg-red-50 text-[var(--muted-foreground)] hover:text-red-500 transition-colors"
                          >
                            <svg width="13" height="13" viewBox="0 0 13 13" fill="none">
                              <path d="M2 4h9M5 4V2h3v2M4 4l.5 7h4L9 4" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
                            </svg>
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      <MenuItemFormModal open={modalOpen} onOpenChange={setModalOpen} item={editItem} categories={categories.length ? categories : ["General"]} onSubmit={handleSubmit} />

      <ConfirmDialog
        open={!!deleteTarget}
        onOpenChange={(open) => !open && setDeleteTarget(null)}
        title="Remove item?"
        description="This item will be removed from your menu immediately."
        confirmLabel="Remove"
        destructive
        onConfirm={handleDelete}
      />
    </>
  );
}
