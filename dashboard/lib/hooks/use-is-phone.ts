"use client";

import { useSyncExternalStore } from "react";

// Tailwind's `md` breakpoint: below it the dashboard uses its phone layouts.
const QUERY = "(max-width: 767px)";

function subscribe(onChange: () => void) {
  if (typeof window === "undefined" || !window.matchMedia) return () => {};
  const mql = window.matchMedia(QUERY);
  mql.addEventListener("change", onChange);
  return () => mql.removeEventListener("change", onChange);
}

/** True on phone-width screens. Server render (and test DOMs without matchMedia) assume desktop. */
export function useIsPhone(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => (typeof window !== "undefined" && window.matchMedia ? window.matchMedia(QUERY).matches : false),
    () => false,
  );
}
