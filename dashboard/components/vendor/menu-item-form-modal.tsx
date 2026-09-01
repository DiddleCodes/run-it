"use client";

import { FormEvent, useState } from "react";
import { BtnPrimary, BtnSecondary } from "@/components/shared/buttons";
import { Modal } from "@/components/shared/modal";
import { PhotoUploadField } from "./photo-upload-field";
import { nairaToKobo } from "@/lib/format";
import { uploadImageToS3 } from "@/lib/api/upload-to-s3";
import { MenuItem } from "@/lib/api/vendor-client";

interface MenuItemFormModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  item: MenuItem | null; // null = adding a new item
  categories: string[]; // distinct categories already used by this vendor's own items
  onSubmit: (dto: { name: string; description?: string; price: number; photoUrl?: string; category: string }) => Promise<void>;
}

export function MenuItemFormModal({ open, onOpenChange, item, categories, onSubmit }: MenuItemFormModalProps) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [priceNaira, setPriceNaira] = useState("");
  const [category, setCategory] = useState("");
  const [newCategory, setNewCategory] = useState("");
  const [addingCategory, setAddingCategory] = useState(false);
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  // React's documented "adjusting state during rendering" pattern (not an
  // Effect): reset the form's fields the moment `open` transitions to
  // true, comparing against a tracked previous value right here in the
  // render body rather than syncing via a useEffect after the fact.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) {
      setName(item?.name ?? "");
      setDescription(item?.description ?? "");
      setPriceNaira(item ? (item.price / 100).toFixed(2) : "");
      setCategory(item?.category ?? categories[0] ?? "");
      setAddingCategory(false);
      setNewCategory("");
      setPhotoFile(null);
      setError("");
    }
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const finalCategory = addingCategory ? newCategory.trim() : category;
    if (!name.trim() || !finalCategory || !priceNaira) {
      setError("Name, category, and price are required.");
      return;
    }
    const price = nairaToKobo(priceNaira);
    if (!Number.isFinite(price) || price < 1) {
      setError("Enter a valid price.");
      return;
    }

    setSaving(true);
    setError("");
    try {
      let photoUrl = item?.photoUrl ?? undefined;
      if (photoFile) {
        photoUrl = await uploadImageToS3(photoFile, "menu-item-photo");
      }
      await onSubmit({ name: name.trim(), description: description.trim() || undefined, price, photoUrl, category: finalCategory });
      onOpenChange(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open={open} onOpenChange={onOpenChange} title={item ? "Edit menu item" : "Add menu item"}>
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label htmlFor="menu-item-name" className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">
            Item name
          </label>
          <input
            id="menu-item-name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Jollof Rice Bowl"
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
          />
        </div>
        <div>
          <label htmlFor="menu-item-description" className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">
            Description
          </label>
          <textarea
            id="menu-item-description"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            rows={2}
            className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm resize-none focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
          />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label htmlFor="menu-item-price" className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">
              Price (₦)
            </label>
            <input
              id="menu-item-price"
              type="number"
              step="0.01"
              min="0"
              value={priceNaira}
              onChange={(e) => setPriceNaira(e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
            />
          </div>
          <div>
            <label htmlFor="menu-item-category" className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">
              Category
            </label>
            {addingCategory ? (
              <input
                id="menu-item-category"
                autoFocus
                value={newCategory}
                onChange={(e) => setNewCategory(e.target.value)}
                placeholder="New category"
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
              />
            ) : (
              <select
                id="menu-item-category"
                value={category}
                onChange={(e) => {
                  if (e.target.value === "__new__") {
                    setAddingCategory(true);
                  } else {
                    setCategory(e.target.value);
                  }
                }}
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
              >
                {categories.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
                <option value="__new__">+ New category</option>
              </select>
            )}
          </div>
        </div>

        <PhotoUploadField label="Photo" existingUrl={item?.photoUrl ?? null} file={photoFile} onFileChange={setPhotoFile} />

        {error && <p className="text-xs text-red-500">{error}</p>}

        <div className="flex justify-end gap-2 pt-2">
          <BtnSecondary type="button" onClick={() => onOpenChange(false)}>
            Cancel
          </BtnSecondary>
          <BtnPrimary type="submit" disabled={saving}>
            {saving ? "Saving…" : item ? "Save changes" : "Add item"}
          </BtnPrimary>
        </div>
      </form>
    </Modal>
  );
}
