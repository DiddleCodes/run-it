import { EscrowStatus, OrderStatus, TransferLegStatus } from '@prisma/client';

/** A restaurant's payout on one order, as its Earnings page shows it. */
export type PayoutState = 'settled' | 'pending' | 'failed';

/** What the earnings rules need about one order and its escrow. */
export interface EarningsRow {
  orderId: string;
  pickupCode: string;
  orderStatus: OrderStatus;
  deliveredAt: Date | null;
  escrowStatus: EscrowStatus;
  restaurantTransferStatus: TransferLegStatus;
  foodSubtotal: number;
  restaurantCommission: number;
  restaurantPlatformFee: number;
  restaurantShare: number;
}

/**
 * Where a restaurant's money for this order stands — or null when the order
 * isn't earnings at all. Only a *delivered* order the customer wasn't
 * refunded for earns anything: a cancelled or refunded order never counts as
 * pending or settled (counting those is the mistake that once put the
 * admin's platform revenue above GMV).
 */
export function classifyPayout(row: EarningsRow): PayoutState | null {
  if (row.orderStatus !== 'delivered' || row.escrowStatus === 'refunded') return null;
  if (row.restaurantTransferStatus === 'success') return 'settled';
  if (row.restaurantTransferStatus === 'failed') return 'failed';
  // Delivered, but the transfer hasn't gone out yet or hasn't confirmed.
  return 'pending';
}

export interface EarningsLine {
  orderId: string;
  pickupCode: string;
  deliveredAt: Date | null;
  foodSubtotalKobo: number;
  /** Bridgit's whole cut: the commission plus the flat platform fee. */
  commissionKobo: number;
  payoutKobo: number;
  payoutStatus: PayoutState;
}

export function toLine(row: EarningsRow): EarningsLine | null {
  const payoutStatus = classifyPayout(row);
  if (!payoutStatus) return null;
  return {
    orderId: row.orderId,
    pickupCode: row.pickupCode,
    deliveredAt: row.deliveredAt,
    foodSubtotalKobo: row.foodSubtotal,
    commissionKobo: row.restaurantCommission + row.restaurantPlatformFee,
    payoutKobo: row.restaurantShare,
    payoutStatus,
  };
}

export interface EarningsTotals {
  settledKobo: number;
  settledCount: number;
  pendingKobo: number;
  pendingCount: number;
  failedKobo: number;
  failedCount: number;
}

export function totalEarnings(rows: EarningsRow[]): EarningsTotals {
  const totals: EarningsTotals = { settledKobo: 0, settledCount: 0, pendingKobo: 0, pendingCount: 0, failedKobo: 0, failedCount: 0 };
  for (const row of rows) {
    const state = classifyPayout(row);
    if (!state) continue;
    totals[`${state}Kobo`] += row.restaurantShare;
    totals[`${state}Count`] += 1;
  }
  return totals;
}
