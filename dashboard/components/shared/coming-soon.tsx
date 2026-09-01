import { PageHeader } from "@/components/layout/page-header";
import { EmptyState } from "./empty-state";

interface ComingSoonProps {
  title: string;
  breadcrumb: string;
}

/** Real, guarded, honest placeholder — not fabricated data — for nav targets whose backend data wiring lands in a later task. */
export function ComingSoon({ title, breadcrumb }: ComingSoonProps) {
  return (
    <>
      <PageHeader title={title} breadcrumb={breadcrumb} />
      <EmptyState title="Coming in a later task" description={`${title} will be wired up to real backend data in a follow-up task.`} />
    </>
  );
}
