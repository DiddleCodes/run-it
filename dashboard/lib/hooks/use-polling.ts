"use client";

import { useEffect, useRef } from "react";

/**
 * Re-runs `fn` on an interval while the tab is visible. Pauses (doesn't
 * fire) while backgrounded — resumes on the next visible tick rather than
 * catching up immediately, which is fine for a "near real-time" queue.
 */
export function usePolling(fn: () => void, intervalMs: number) {
  const fnRef = useRef(fn);
  useEffect(() => {
    fnRef.current = fn;
  });

  useEffect(() => {
    const id = setInterval(() => {
      if (document.visibilityState === "visible") fnRef.current();
    }, intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
}
