import { ReactNode } from "react";

interface EmptyStateProps {
  title: string;
  description?: string;
  icon?: ReactNode;
  action?: ReactNode;
}

const defaultIcon = (
  <svg width="28" height="28" viewBox="0 0 28 28" fill="none" className="text-[var(--muted-foreground)]">
    <circle cx="14" cy="14" r="12" stroke="currentColor" strokeWidth="1.5" strokeDasharray="4 3" />
    <path d="M9 14h10M14 9v10" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
  </svg>
);

export function EmptyState({ title, description, icon, action }: EmptyStateProps) {
  return (
    <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] p-12 text-center">
      <div className="w-16 h-16 rounded-2xl bg-[var(--secondary)] flex items-center justify-center mx-auto mb-4">{icon ?? defaultIcon}</div>
      <h3 className="font-semibold text-[var(--foreground)] mb-1.5">{title}</h3>
      {description && <p className="text-sm text-[var(--muted-foreground)] max-w-xs mx-auto mb-4">{description}</p>}
      {action}
    </div>
  );
}
