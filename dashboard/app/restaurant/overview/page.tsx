import { PageHeader } from "@/components/layout/page-header";
import { StatCard } from "@/components/shared/stat-card";

// Real backend order/revenue data lands in Task 13b — this page proves the
// role-guarded shell renders correctly for a restaurant account. StatCard's
// own `loading` skeleton state is used rather than inventing numbers.
export default function RestaurantOverviewPage() {
  return (
    <>
      <PageHeader title="Overview" subtitle="Your restaurant's activity at a glance." breadcrumb="Restaurant" />
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard icon={<span />} label="Today's orders" value="" loading />
        <StatCard icon={<span />} label="Today's revenue" value="" loading />
        <StatCard icon={<span />} label="Avg. prep time" value="" loading />
        <StatCard icon={<span />} label="Menu items live" value="" loading />
      </div>
      <p className="text-sm text-[var(--muted-foreground)] mt-6">
        Live order and revenue data is wired up in a later task — this page confirms the shell, navigation, and role guard for a
        restaurant account are all real and working.
      </p>
    </>
  );
}
