"use client";

import { useEffect, useState } from "react";
import { BtnPrimary } from "@/components/shared/buttons";
import { Bank, PayoutAccount, VendorApiError, vendorClient } from "@/lib/api/vendor-client";
import { BankPicker } from "./bank-picker";

type Mode = "summary" | "edit" | "confirm";

function maskAccountNumber(accountNumber: string): string {
  return `${"•".repeat(6)} ${accountNumber.slice(-4)}`;
}

/**
 * Reusable payout/bank-verification component — rebuilt for web from the
 * same proven mobile pattern (bank picker -> account number -> Verify ->
 * "is this you?" confirmation). POST /payout-accounts verifies against
 * Paystack and persists in one atomic call; the resolved accountName in the
 * response IS the "is this you?" proof, so "Yes, that's me" is a purely
 * client-side acknowledgement, not a second network call.
 */
export function PayoutSection({ userId, initialAccount }: { userId: string; initialAccount: PayoutAccount | null }) {
  const [account, setAccount] = useState<PayoutAccount | null>(initialAccount);
  const [mode, setMode] = useState<Mode>(initialAccount ? "summary" : "edit");
  const [banks, setBanks] = useState<Bank[]>([]);
  const [bank, setBank] = useState<Bank | null>(null);
  const [accountNumber, setAccountNumber] = useState("");
  const [bankError, setBankError] = useState("");
  const [numberError, setNumberError] = useState("");
  const [verifyError, setVerifyError] = useState("");
  const [verifying, setVerifying] = useState(false);

  useEffect(() => {
    vendorClient.getBanks().then(setBanks).catch(() => {});
  }, []);

  const bankName = (code: string) => banks.find((b) => b.code === code)?.name ?? code;

  async function handleVerify() {
    setBankError("");
    setNumberError("");
    setVerifyError("");

    let hasError = false;
    if (!bank) {
      setBankError("Choose your bank.");
      hasError = true;
    }
    const digits = accountNumber.trim();
    if (digits.length !== 10 || !/^\d{10}$/.test(digits)) {
      setNumberError("Enter a valid 10-digit account number.");
      hasError = true;
    }
    if (hasError) return;

    setVerifying(true);
    try {
      const saved = await vendorClient.savePayoutAccount({ userId, bankCode: bank!.code, accountNumber: digits });
      setAccount(saved);
      setMode("confirm");
    } catch (err) {
      setVerifyError(err instanceof VendorApiError ? err.message : "Couldn't reach the server — check your connection and try again.");
    } finally {
      setVerifying(false);
    }
  }

  if (mode === "summary" && account) {
    return (
      <div>
        <div className="p-4 rounded-xl bg-gradient-to-br from-[#1A0E12] to-[#2D1220] text-white mb-4">
          <div className="flex items-center justify-between mb-4">
            <span className="text-xs text-white/50">Bank account</span>
            <svg width="28" height="20" viewBox="0 0 28 20" fill="none">
              <rect width="28" height="20" rx="3" fill="white" fillOpacity="0.1" />
              <circle cx="10" cy="10" r="6" fill="#7A1636" fillOpacity="0.7" />
              <circle cx="18" cy="10" r="6" fill="#D99A18" fillOpacity="0.7" />
            </svg>
          </div>
          <p className="font-mono text-base tracking-widest">{maskAccountNumber(account.accountNumber)}</p>
          <div className="flex justify-between items-end mt-3">
            <div>
              <p className="text-[10px] text-white/40 uppercase tracking-wide">Account holder</p>
              <p className="text-sm font-medium">{account.accountName}</p>
            </div>
            <div className="text-right">
              <p className="text-[10px] text-white/40 uppercase tracking-wide">Bank</p>
              <p className="text-sm font-medium">{bankName(account.bankCode)}</p>
            </div>
          </div>
        </div>
        <div className="space-y-2 text-sm">
          <p className="text-xs text-[var(--muted-foreground)]">Payouts are processed once delivery is confirmed for each order.</p>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs px-2 py-1 rounded-lg bg-emerald-50 text-emerald-700">
              <span className="w-2 h-2 rounded-full bg-emerald-400" />
              Account verified
            </div>
            <button onClick={() => setMode("edit")} className="text-xs text-[var(--primary)] hover:underline">
              Edit
            </button>
          </div>
        </div>
      </div>
    );
  }

  if (mode === "confirm" && account) {
    return (
      <div className="p-5 rounded-xl border border-emerald-200 bg-emerald-50 text-center">
        <p className="text-xs text-emerald-700 mb-1">Is this you?</p>
        <p className="font-fraunces text-xl font-semibold text-[var(--primary)] mb-1">{account.accountName}</p>
        <p className="text-sm text-[var(--muted-foreground)] font-mono mb-4">
          {bankName(account.bankCode)} · {maskAccountNumber(account.accountNumber)}
        </p>
        <div className="flex flex-col gap-2">
          <BtnPrimary onClick={() => setMode("summary")}>Yes, that&apos;s me</BtnPrimary>
          <button onClick={() => setMode("edit")} className="text-xs text-[var(--muted-foreground)] hover:underline">
            Not you? Edit the details
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <BankPicker value={bank} onChange={setBank} errorText={bankError} />
      <div>
        <label className="block text-xs text-[var(--muted-foreground)] mb-1.5">Account number</label>
        <input
          value={accountNumber}
          onChange={(e) => setAccountNumber(e.target.value.replace(/\D/g, "").slice(0, 10))}
          placeholder="0123456789"
          className={`w-full px-3 py-2 rounded-lg border text-sm focus:border-[var(--primary)] focus:outline-none bg-[var(--secondary)] ${
            numberError ? "border-red-300" : "border-[var(--border)]"
          }`}
        />
        {numberError && <p className="text-xs text-red-500 mt-1">{numberError}</p>}
      </div>
      {verifyError && (
        <div className="flex items-start gap-2 p-3 rounded-lg bg-rose-50 border border-rose-200 text-rose-700 text-xs">
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" className="flex-shrink-0 mt-0.5">
            <circle cx="8" cy="8" r="7" stroke="currentColor" strokeWidth="1.5" />
            <path d="M8 5v4M8 10.5v.01" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
          {verifyError}
        </div>
      )}
      <div className="flex gap-2">
        {account && (
          <button onClick={() => setMode("summary")} className="text-xs text-[var(--muted-foreground)] hover:underline">
            Cancel
          </button>
        )}
        <BtnPrimary onClick={handleVerify} disabled={verifying} className="ml-auto">
          {verifying ? "Verifying…" : "Verify"}
        </BtnPrimary>
      </div>
    </div>
  );
}
