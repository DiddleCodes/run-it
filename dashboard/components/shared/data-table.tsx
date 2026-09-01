"use client";

import { ReactNode, useMemo, useState } from "react";

export interface Column<T> {
  key: string;
  header: string;
  sortable?: boolean;
  render?: (row: T) => ReactNode;
  className?: string;
}

interface DataTableProps<T extends { id: string }> {
  columns: Column<T>[];
  data: T[];
  loading?: boolean;
  emptyTitle?: string;
  emptyDescription?: string;
  pageSize?: number;
  onRowClick?: (row: T) => void;
}

function SkeletonRow({ cols }: { cols: number }) {
  return (
    <tr>
      {Array.from({ length: cols }).map((_, i) => (
        <td key={i} className="px-4 py-3">
          <div className="skeleton-shimmer h-4 rounded" style={{ width: `${60 + ((i * 17) % 30)}%` }} />
        </td>
      ))}
    </tr>
  );
}

export function DataTable<T extends { id: string }>({
  columns,
  data,
  loading,
  emptyTitle = "No results",
  emptyDescription = "Nothing to display here.",
  pageSize = 10,
  onRowClick,
}: DataTableProps<T>) {
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<"asc" | "desc">("asc");
  const [page, setPage] = useState(1);

  function handleSort(key: string) {
    if (sortKey === key) {
      setSortDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setSortKey(key);
      setSortDir("asc");
    }
  }

  const sorted = useMemo(() => {
    if (!sortKey) return data;
    return [...data].sort((a, b) => {
      const av = (a as Record<string, unknown>)[sortKey] ?? "";
      const bv = (b as Record<string, unknown>)[sortKey] ?? "";
      const cmp = av < bv ? -1 : av > bv ? 1 : 0;
      return sortDir === "asc" ? cmp : -cmp;
    });
  }, [data, sortKey, sortDir]);

  const totalPages = Math.ceil(sorted.length / pageSize);
  const paged = sorted.slice((page - 1) * pageSize, page * pageSize);

  return (
    <div className="bg-card rounded-[var(--radius)] border border-[var(--border)] shadow-[0_1px_8px_rgba(0,0,0,0.06)] overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-[var(--border)] bg-[var(--secondary)]">
              {columns.map((col) => (
                <th
                  key={col.key}
                  className={`px-4 py-3 text-left text-xs font-semibold text-[var(--muted-foreground)] uppercase tracking-wide select-none ${
                    col.sortable ? "cursor-pointer hover:text-[var(--foreground)] transition-colors" : ""
                  } ${col.className ?? ""}`}
                  onClick={() => col.sortable && handleSort(col.key)}
                >
                  <span className="flex items-center gap-1">
                    {col.header}
                    {col.sortable && (
                      <span className={`opacity-40 ${sortKey === col.key ? "opacity-100 text-[var(--primary)]" : ""}`}>
                        {sortKey === col.key ? (sortDir === "asc" ? " ↑" : " ↓") : " ↕"}
                      </span>
                    )}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {loading ? (
              Array.from({ length: 5 }).map((_, i) => <SkeletonRow key={i} cols={columns.length} />)
            ) : paged.length === 0 ? (
              <tr>
                <td colSpan={columns.length} className="py-16 text-center">
                  <div className="flex flex-col items-center gap-2">
                    <span className="text-4xl opacity-20">◎</span>
                    <p className="font-medium text-[var(--foreground)]">{emptyTitle}</p>
                    <p className="text-[var(--muted-foreground)] text-xs">{emptyDescription}</p>
                  </div>
                </td>
              </tr>
            ) : (
              paged.map((row) => (
                <tr
                  key={row.id}
                  className={`border-b border-[var(--border)] last:border-0 table-row-hover ${onRowClick ? "cursor-pointer" : ""}`}
                  onClick={() => onRowClick?.(row)}
                >
                  {columns.map((col) => (
                    <td key={col.key} className={`px-4 py-3 text-[var(--card-foreground)] ${col.className ?? ""}`}>
                      {col.render ? col.render(row) : String((row as Record<string, unknown>)[col.key] ?? "")}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      {!loading && totalPages > 1 && (
        <div className="flex items-center justify-between px-4 py-3 border-t border-[var(--border)] bg-[var(--secondary)]">
          <span className="text-xs text-[var(--muted-foreground)]">
            Showing {(page - 1) * pageSize + 1}–{Math.min(page * pageSize, sorted.length)} of {sorted.length}
          </span>
          <div className="flex gap-1">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="px-2.5 py-1 rounded-md text-xs border border-[var(--border)] disabled:opacity-40 hover:bg-[var(--muted)] transition-colors"
            >
              ← Prev
            </button>
            {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
              <button
                key={p}
                onClick={() => setPage(p)}
                className={`px-2.5 py-1 rounded-md text-xs border transition-colors ${
                  p === page ? "bg-[var(--primary)] text-white border-[var(--primary)]" : "border-[var(--border)] hover:bg-[var(--muted)]"
                }`}
              >
                {p}
              </button>
            ))}
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              className="px-2.5 py-1 rounded-md text-xs border border-[var(--border)] disabled:opacity-40 hover:bg-[var(--muted)] transition-colors"
            >
              Next →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
