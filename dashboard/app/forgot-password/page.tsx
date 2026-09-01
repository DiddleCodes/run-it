"use client";

import { motion } from "framer-motion";
import { FormEvent, useState } from "react";
import { AuthShell } from "@/components/auth/auth-shell";

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState("");

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (!email) {
      setError("Please enter your email address.");
      return;
    }
    setError("");
    setLoading(true);

    try {
      await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      // Always show the same success state, whether or not the email
      // matched an account — the backend already guarantees this at the
      // API level; the UI just doesn't branch on it either.
      setSubmitted(true);
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthShell>
      <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.35, ease: "easeOut" }}>
        {submitted ? (
          <div className="text-center py-2">
            <div className="inline-flex w-10 h-10 rounded-full bg-emerald-500/15 items-center justify-center mb-3">
              <svg width="18" height="18" viewBox="0 0 16 16" fill="none" className="text-emerald-400">
                <path d="M5 8l2 2 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
            <p className="text-sm text-white/80 mb-1">Check your email</p>
            <p className="text-xs text-white/40 leading-relaxed">
              If an account exists for <span className="text-white/60">{email}</span>, we&apos;ve sent a link to reset your password.
            </p>
            <a href="/login" className="inline-block mt-5 text-xs text-[#D99A18] hover:text-[#D99A18]/80 transition-colors">
              ← Back to sign in
            </a>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <p className="text-sm text-white/70 mb-4">Enter the email address for your account and we&apos;ll send you a link to reset your password.</p>
              <label htmlFor="email" className="block text-xs font-medium text-white/60 mb-1.5">
                Email address
              </label>
              <input
                id="email"
                type="email"
                autoComplete="username"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
                className="w-full px-3 py-2.5 rounded-lg bg-white/5 border border-white/10 text-white text-sm placeholder:text-white/25 focus:border-[#7A1636] focus:outline-none focus:ring-2 focus:ring-[#7A1636]/20 transition-all"
              />
            </div>

            {error && <p className="text-xs text-red-400">{error}</p>}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 rounded-lg bg-gradient-to-r from-[#7A1636] to-[#5A0E25] text-white text-sm font-semibold transition-all hover:from-[#5A0E25] hover:to-[#3A0818] active:scale-[0.98] disabled:opacity-50"
            >
              {loading ? "Sending…" : "Send reset link"}
            </button>

            <a href="/login" className="block text-center text-xs text-white/40 hover:text-white/60 transition-colors">
              ← Back to sign in
            </a>
          </form>
        )}
      </motion.div>
    </AuthShell>
  );
}
