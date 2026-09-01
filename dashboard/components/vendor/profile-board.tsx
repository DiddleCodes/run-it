"use client";

import { useState } from "react";
import { BtnPrimary, BtnSecondary } from "@/components/shared/buttons";
import { toast } from "@/lib/toast";
import { uploadImageToS3 } from "@/lib/api/upload-to-s3";
import { PayoutAccount, Vendor, VendorApiError, vendorClient } from "@/lib/api/vendor-client";
import { CategoryPicker } from "./category-picker";
import { PayoutSection } from "./payout-section";

export function ProfileBoard({
  userId,
  initialVendor,
  initialPayoutAccount,
}: {
  userId: string;
  initialVendor: Vendor | null;
  initialPayoutAccount: PayoutAccount | null;
}) {
  const [vendor, setVendor] = useState<Vendor | null>(initialVendor);
  const [editing, setEditing] = useState(!initialVendor);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const [name, setName] = useState(initialVendor?.businessName ?? "");
  const [category, setCategory] = useState(initialVendor?.category ?? "");
  const [description, setDescription] = useState(initialVendor?.description ?? "");
  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [logoPreview, setLogoPreview] = useState<string | null>(null);

  function startEditing() {
    setName(vendor?.businessName ?? "");
    setCategory(vendor?.category ?? "");
    setDescription(vendor?.description ?? "");
    setLogoFile(null);
    setError("");
    setEditing(true);
  }

  async function handleLogoPick(file: File | null) {
    setLogoFile(file);
    if (file) setLogoPreview(URL.createObjectURL(file));
    else setLogoPreview(null);
  }

  async function handleSave() {
    if (!name.trim() || !category) {
      setError("Business name and category are required.");
      return;
    }
    setSaving(true);
    setError("");
    try {
      let logoUrl = vendor?.logoUrl ?? undefined;
      if (logoFile) {
        logoUrl = await uploadImageToS3(logoFile, "vendor-logo");
      }
      const saved = await vendorClient.upsertVendorProfile({
        businessName: name.trim(),
        category,
        description: description.trim() || undefined,
        logoUrl,
      });
      setVendor(saved);
      setEditing(false);
      toast.success("Profile updated successfully");
    } catch (err) {
      setError(err instanceof VendorApiError ? err.message : "Something went wrong. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  const displayLogo = logoPreview ?? vendor?.logoUrl ?? null;

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div className="lg:col-span-2 bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] p-6">
        <div className="flex items-center justify-between mb-5">
          <h2 className="font-semibold text-[var(--foreground)]">Business information</h2>
          {!editing ? (
            <BtnSecondary onClick={startEditing}>Edit</BtnSecondary>
          ) : (
            <div className="flex gap-2">
              {vendor && <BtnSecondary onClick={() => setEditing(false)}>Cancel</BtnSecondary>}
              <BtnPrimary onClick={handleSave} disabled={saving}>
                {saving ? "Saving…" : vendor ? "Save changes" : "Create profile"}
              </BtnPrimary>
            </div>
          )}
        </div>

        {error && <p className="text-xs text-red-500 mb-4">{error}</p>}

        <div className="flex items-start gap-5 mb-5">
          <div className="relative">
            <div className="w-20 h-20 rounded-xl overflow-hidden bg-[var(--secondary)] flex items-center justify-center">
              {displayLogo ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={displayLogo} alt="Logo" className="w-full h-full object-cover" />
              ) : (
                <span className="text-3xl opacity-20">🏪</span>
              )}
            </div>
            {editing && (
              <label className="absolute -bottom-1.5 -right-1.5 w-6 h-6 rounded-full bg-[var(--primary)] text-white flex items-center justify-center shadow cursor-pointer">
                <input
                  type="file"
                  accept="image/jpeg,image/png,image/webp"
                  className="hidden"
                  onChange={(e) => handleLogoPick(e.target.files?.[0] ?? null)}
                />
                <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
                  <path d="M7 1l2 2-5 5H2V6l5-5z" stroke="currentColor" strokeWidth="1.2" strokeLinejoin="round" />
                </svg>
              </label>
            )}
          </div>
          <div className="flex-1">
            <p className="text-xs text-[var(--muted-foreground)] mb-1">Restaurant name</p>
            {editing ? (
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
              />
            ) : (
              <p className="font-semibold text-[var(--foreground)]">{vendor?.businessName}</p>
            )}
          </div>
        </div>

        <div className="space-y-4">
          <div>
            {editing ? (
              <CategoryPicker value={category} onChange={setCategory} />
            ) : (
              <>
                <label className="block text-xs text-[var(--muted-foreground)] mb-1.5">Category</label>
                <p className="text-sm text-[var(--foreground)]">{vendor?.category}</p>
              </>
            )}
          </div>
          <div>
            <label className="block text-xs text-[var(--muted-foreground)] mb-1.5">Description</label>
            {editing ? (
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={3}
                className="w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm resize-none focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)]"
              />
            ) : (
              <p className="text-sm text-[var(--foreground)] leading-relaxed">{vendor?.description || "—"}</p>
            )}
          </div>
        </div>
      </div>

      <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] p-6">
        <h2 className="font-semibold text-[var(--foreground)] mb-5">Payouts</h2>
        <PayoutSection userId={userId} initialAccount={initialPayoutAccount} />
      </div>
    </div>
  );
}
