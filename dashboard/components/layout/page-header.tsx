import { ReactNode } from "react";

interface PageHeaderProps {
  title: string;
  subtitle?: string;
  breadcrumb?: string;
  action?: ReactNode;
}

export function PageHeader({ title, subtitle, breadcrumb, action }: PageHeaderProps) {
  return (
    <div className="flex items-start justify-between mb-6">
      <div>
        {breadcrumb && <p className="text-xs text-[var(--muted-foreground)] mb-1">{breadcrumb}</p>}
        <h1 className="font-fraunces text-2xl font-semibold text-[var(--foreground)]">{title}</h1>
        {subtitle && <p className="text-sm text-[var(--muted-foreground)] mt-0.5">{subtitle}</p>}
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  );
}
