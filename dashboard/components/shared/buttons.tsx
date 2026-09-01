import { ReactNode } from "react";

interface BtnProps {
  children: ReactNode;
  onClick?: () => void;
  disabled?: boolean;
  type?: "button" | "submit";
  className?: string;
}

export function BtnPrimary({ children, onClick, disabled, type = "button", className }: BtnProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-[var(--primary)] text-white text-sm font-medium transition-all disabled:opacity-50 hover:bg-[#5A0E25] hover:shadow-[0_4px_20px_rgba(122,22,54,0.3)] active:scale-[0.98] ${className ?? ""}`}
    >
      {children}
    </button>
  );
}

export function BtnSecondary({ children, onClick, disabled, type = "button", className }: BtnProps) {
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`inline-flex items-center gap-2 px-4 py-2 rounded-lg border border-[var(--border)] text-sm font-medium transition-colors hover:bg-[var(--muted)] active:scale-[0.98] disabled:opacity-50 ${className ?? ""}`}
    >
      {children}
    </button>
  );
}
