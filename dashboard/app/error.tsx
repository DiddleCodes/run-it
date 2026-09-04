"use client";

import * as Sentry from "@sentry/nextjs";
import { useEffect } from "react";
import { EmptyState } from "@/components/shared/empty-state";

// Task 36: nested boundary wrapping everything under the root layout —
// admin/restaurant shell chrome (sidebar, top bar) stays intact when a
// page-level render error occurs, since this sits below that shell's own
// layout.tsx in the component hierarchy. Reports via Sentry the same way
// global-error.tsx does for errors that escape the root layout itself.
export default function ErrorBoundary({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => {
    Sentry.captureException(error);
  }, [error]);

  return (
    <div className="p-6">
      <EmptyState
        title="Something went wrong"
        description="This page hit an unexpected error. It's been reported — try again, or come back in a moment."
        action={
          <button
            onClick={() => retry()}
            className="px-4 py-2 rounded-lg bg-[#7A1636] text-white text-sm font-medium hover:bg-[#5A0E25] transition-colors"
          >
            Try again
          </button>
        }
      />
    </div>
  );
}
