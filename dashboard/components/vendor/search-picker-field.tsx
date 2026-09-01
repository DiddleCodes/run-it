"use client";

import { useEffect, useRef, useState } from "react";

interface SearchPickerFieldProps<T> {
  label: string;
  displayValue: string;
  placeholder: string;
  fetchItems: () => Promise<T[]>;
  getKey: (item: T) => string;
  getLabel: (item: T) => string;
  onSelect: (item: T) => void;
  errorText?: string;
}

/**
 * Generic trigger-field-opens-search-list picker, backed by a real fetch —
 * mirrors the mobile app's CategoryPickerField/BankPickerField pattern
 * (loading spinner, "couldn't load — tap to retry" error state, search
 * filter). Shared by CategoryPicker and BankPicker rather than duplicating
 * the popover logic twice.
 */
export function SearchPickerField<T>({ label, displayValue, placeholder, fetchItems, getKey, getLabel, onSelect, errorText }: SearchPickerFieldProps<T>) {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<T[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState(false);
  const [query, setQuery] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);

  // No synchronous setState here — every state update happens inside a
  // promise callback (after the effect's own synchronous execution has
  // already finished), so this is safe to call directly from the mount
  // effect below.
  function fetchAndSet() {
    fetchItems()
      .then(setItems)
      .catch(() => setLoadError(true))
      .finally(() => setLoading(false));
  }

  function retry() {
    setLoading(true);
    setLoadError(false);
    fetchAndSet();
  }

  useEffect(() => {
    fetchAndSet();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const filtered = (items ?? []).filter((item) => getLabel(item).toLowerCase().includes(query.toLowerCase()));

  return (
    <div ref={containerRef} className="relative">
      <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">{label}</label>
      <button
        type="button"
        onClick={() => {
          if (loading) return;
          if (loadError) {
            retry();
            return;
          }
          setOpen((o) => !o);
        }}
        className={`w-full flex items-center justify-between px-3 py-2 rounded-lg border text-sm text-left transition-all bg-[var(--secondary)] ${
          errorText ? "border-red-300" : "border-[var(--border)]"
        } focus:border-[var(--primary)] focus:outline-none`}
      >
        <span className={displayValue ? "text-[var(--foreground)]" : "text-[var(--muted-foreground)]"}>
          {loading ? "Loading…" : loadError ? "Couldn't load — tap to retry" : displayValue || placeholder}
        </span>
        {loadError ? (
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" className="text-[var(--muted-foreground)] flex-shrink-0">
            <path d="M12 4a5 5 0 10.9 5.5M12 4V1.5M12 4H9.5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        ) : (
          <svg width="12" height="12" viewBox="0 0 12 12" fill="none" className="text-[var(--muted-foreground)] flex-shrink-0">
            <path d="M3 4.5l3 3 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        )}
      </button>
      {errorText && <p className="text-xs text-red-500 mt-1">{errorText}</p>}

      {open && !loading && !loadError && (
        <div className="absolute z-20 mt-1 w-full bg-card border border-[var(--border)] rounded-lg shadow-xl max-h-64 overflow-hidden flex flex-col">
          <input
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search…"
            className="px-3 py-2 text-sm border-b border-[var(--border)] focus:outline-none"
          />
          <div className="overflow-y-auto">
            {filtered.length === 0 ? (
              <p className="px-3 py-3 text-xs text-[var(--muted-foreground)]">No matches.</p>
            ) : (
              filtered.map((item) => (
                <button
                  key={getKey(item)}
                  type="button"
                  onClick={() => {
                    onSelect(item);
                    setOpen(false);
                    setQuery("");
                  }}
                  className="w-full text-left px-3 py-2 text-sm hover:bg-[var(--secondary)] transition-colors"
                >
                  {getLabel(item)}
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}
