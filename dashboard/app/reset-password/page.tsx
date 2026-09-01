"use client";

import { motion } from "framer-motion";
import { useSearchParams } from "next/navigation";
import { FormEvent, Suspense, useState } from "react";
import { AuthShell } from "@/components/auth/auth-shell";

function ResetPasswordForm() {
  const searchParams = useSearchParams();
  const token = searchParams.get("token") ?? "";

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [done, setDone] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!token) {
      setError("This reset link is missing its token.");
      return;
    }
    if (password.length < 8) {
      setError("Password must be at least 8 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setError("Passwords do not match.");
      return;
    }

    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, newPassword: password }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.message ?? "This reset link is invalid or has expired.");
        return;
      }
      setDone(true);
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  if (done) {
    return (
      <div className="text-center py-2">
        <div className="inline-flex w-10 h-10 rounded-full bg-emerald-500/15 items-center justify-center mb-3">
          <svg width="18" height="18" viewBox="0 0 16 16" fill="none" className="text-emerald-400">
            <path d="M5 8l2 2 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
        <p className="text-sm text-white/80 mb-1">Password updated</p>
        <p className="text-xs text-white/40 leading-relaxed">You can now sign in with your new password.</p>
        <a href="/login" className="inline-block mt-5 text-xs text-[#D99A18] hover:text-[#D99A18]/80 transition-colors">
          Continue to sign in →
        </a>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="password" className="block text-xs font-medium text-white/60 mb-1.5">
          New password
        </label>
        <input
          id="password"
          type="password"
          autoComplete="new-password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="••••••••"
          className="w-full px-3 py-2.5 rounded-lg bg-white/5 border border-white/10 text-white text-sm placeholder:text-white/25 focus:border-[#7A1636] focus:outline-none focus:ring-2 focus:ring-[#7A1636]/20 transition-all"
        />
      </div>
      <div>
        <label htmlFor="confirm" className="block text-xs font-medium text-white/60 mb-1.5">
          Confirm new password
        </label>
        <input
          id="confirm"
          type="password"
          autoComplete="new-password"
          value={confirmPassword}
          onChange={(e) => setConfirmPassword(e.target.value)}
          placeholder="••••••••"
          className="w-full px-3 py-2.5 rounded-lg bg-white/5 border border-white/10 text-white text-sm placeholder:text-white/25 focus:border-[#7A1636] focus:outline-none focus:ring-2 focus:ring-[#7A1636]/20 transition-all"
        />
      </div>

      {error && <p className="text-xs text-red-400">{error}</p>}

      <button
        type="submit"
        disabled={loading}
        className="w-full py-2.5 rounded-lg bg-gradient-to-r from-[#7A1636] to-[#5A0E25] text-white text-sm font-semibold transition-all hover:from-[#5A0E25] hover:to-[#3A0818] active:scale-[0.98] disabled:opacity-50"
      >
        {loading ? "Updating…" : "Update password"}
      </button>
    </form>
  );
}

export default function ResetPasswordPage() {
  return (
    <AuthShell>
      <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35, ease: "easeOut" }}>
        <Suspense fallback={null}>
          <ResetPasswordForm />
        </Suspense>
      </motion.div>
    </AuthShell>
  );
}
