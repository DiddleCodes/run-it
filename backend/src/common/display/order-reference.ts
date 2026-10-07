/** "#24513906" — the short order reference people see everywhere (app, pushes, dashboard, bank narrations). */
export function orderReference(orderId: string): string {
  return `#${orderId.slice(-8).toUpperCase()}`;
}
