/** Integer kobo -> "₦1,234.56" — the same convention used throughout the backend and mobile app. */
export function formatKobo(kobo: number): string {
  return `₦${(kobo / 100).toLocaleString("en-NG", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** "₦" input string -> integer kobo, e.g. "1234.5" -> 123450. */
export function nairaToKobo(naira: string): number {
  return Math.round(parseFloat(naira) * 100);
}

export function formatDateTime(iso: string): string {
  return new Date(iso).toLocaleString("en-NG", { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
}
