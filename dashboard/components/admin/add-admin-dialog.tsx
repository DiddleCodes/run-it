"use client";

import { useState } from "react";
import { Modal } from "@/components/shared/modal";
import { toast } from "@/lib/toast";
import { AdminApiError, AdminUserSummary, adminClient } from "@/lib/api/admin-client";

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Adds another dashboard admin. No password here: the new admin gets an
 * email with a link to choose their own.
 */
export function AddAdminDialog({ onAdded }: { onAdded: (user: AdminUserSummary) => void }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const valid = name.trim().length > 0 && EMAIL.test(email.trim());

  function openDialog() {
    setName("");
    setEmail("");
    setError(null);
    setOpen(true);
  }

  async function submit() {
    if (!valid || busy) return;
    setBusy(true);
    setError(null);
    try {
      const { user, inviteSent } = await adminClient.createAdmin({ name: name.trim(), email: email.trim() });
      onAdded(user);
      setOpen(false);
      if (inviteSent) {
        toast.success(`${user.email} is now an admin — we've emailed them a link to choose a password.`);
      } else {
        toast.info(`${user.email} is now an admin, but the invite email didn't send. They can use "Forgot password?" on the sign-in page.`);
      }
    } catch (err) {
      setError(err instanceof AdminApiError ? err.message : "Couldn't add the admin. Please try again.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <button
        onClick={openDialog}
        className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors"
      >
        + Add admin
      </button>

      <Modal
        open={open}
        onOpenChange={setOpen}
        title="Add an admin"
        footer={
          <button
            onClick={submit}
            disabled={!valid || busy}
            className="px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors disabled:opacity-50"
          >
            {busy ? "Adding…" : "Add admin"}
          </button>
        }
      >
        <form
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            void submit();
          }}
        >
          <p className="text-sm text-[var(--muted-foreground)]">
            They&apos;ll have full admin access. We&apos;ll email them a link to choose their own password — you never set or see it.
          </p>
          <label className="block">
            <span className="text-xs font-medium text-[var(--muted-foreground)]">Name</span>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={80}
              autoFocus
              className="mt-1 w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm bg-card focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            />
          </label>
          <label className="block">
            <span className="text-xs font-medium text-[var(--muted-foreground)]">Email</span>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="mt-1 w-full px-3 py-2 rounded-lg border border-[var(--border)] text-sm bg-card focus:outline-none focus:ring-2 focus:ring-[var(--primary)]"
            />
          </label>
          {error && (
            <p role="alert" className="text-sm text-red-600">
              {error}
            </p>
          )}
        </form>
      </Modal>
    </>
  );
}
