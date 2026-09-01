interface StatusBadgeProps {
  status: string;
  size?: "sm" | "md";
}

const config: Record<string, { label: string; className: string }> = {
  new: { label: "New", className: "bg-blue-50 text-blue-700 border-blue-200" },
  preparing: { label: "Preparing", className: "bg-amber-50 text-amber-700 border-amber-200" },
  ready: { label: "Ready", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  completed: { label: "Completed", className: "bg-gray-100 text-gray-600 border-gray-200" },
  cancelled: { label: "Cancelled", className: "bg-red-50 text-red-600 border-red-200" },
  // Real backend OrderStatus values (Order.status) — distinct from the
  // prototype-demo "new/ready/completed" keys above, which the Component
  // Library showcase still uses.
  placed: { label: "New", className: "bg-blue-50 text-blue-700 border-blue-200" },
  ready_for_pickup: { label: "Ready for pickup", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  picked_up: { label: "Out for delivery", className: "bg-indigo-50 text-indigo-700 border-indigo-200" },
  delivered: { label: "Delivered", className: "bg-gray-100 text-gray-600 border-gray-200" },
  pending: { label: "Pending", className: "bg-amber-50 text-amber-700 border-amber-200" },
  approved: { label: "Approved", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  rejected: { label: "Rejected", className: "bg-red-50 text-red-600 border-red-200" },
  open: { label: "Open", className: "bg-red-50 text-red-600 border-red-200" },
  resolved: { label: "Resolved", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  refunded: { label: "Refunded", className: "bg-purple-50 text-purple-700 border-purple-200" },
  active: { label: "Active", className: "bg-emerald-50 text-emerald-700 border-emerald-200" },
  suspended: { label: "Suspended", className: "bg-red-50 text-red-600 border-red-200" },
  draft: { label: "Draft", className: "bg-gray-100 text-gray-500 border-gray-200" },
  processing: { label: "Processing", className: "bg-blue-50 text-blue-700 border-blue-200" },
  student: { label: "Student", className: "bg-sky-50 text-sky-700 border-sky-200" },
  runner: { label: "Runner", className: "bg-violet-50 text-violet-700 border-violet-200" },
  restaurant: { label: "Restaurant", className: "bg-amber-50 text-amber-700 border-amber-200" },
  admin: { label: "Admin", className: "bg-rose-50 text-rose-700 border-rose-200" },
};

export function StatusBadge({ status, size = "md" }: StatusBadgeProps) {
  const cfg = config[status] ?? { label: status, className: "bg-gray-100 text-gray-600 border-gray-200" };
  const sizeClass = size === "sm" ? "text-[10px] px-1.5 py-0.5" : "text-xs px-2 py-0.5";
  return (
    <span className={`inline-flex items-center rounded-full border font-medium ${sizeClass} ${cfg.className}`}>
      <span className="mr-1 inline-block h-1.5 w-1.5 rounded-full bg-current opacity-70" />
      {cfg.label}
    </span>
  );
}
