/** Integer kobo -> "₦1,444.50" — the same format as the app and dashboard. */
export function formatKobo(kobo: number): string {
  const sign = kobo < 0 ? '-' : '';
  const abs = Math.abs(kobo);
  const naira = Math.floor(abs / 100).toLocaleString('en-US');
  return `${sign}₦${naira}.${String(abs % 100).padStart(2, '0')}`;
}
