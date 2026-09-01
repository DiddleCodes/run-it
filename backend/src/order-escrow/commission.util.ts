export interface CommissionRates {
  // 0-1, applied to the food subtotal only — never the delivery fee.
  restaurantCommissionRate: number;
  // 0-1, the runner's share of the delivery fee — never the food subtotal.
  runnerDeliveryFeeShare: number;
}

export interface CommissionShares {
  platformFee: number;
  restaurantShare: number;
  runnerShare: number;
  totalAmount: number;
}

/**
 * Splits a food subtotal and a delivery fee (both integer kobo) into
 * platform/restaurant/runner shares.
 *
 * Commission applies only to the food subtotal; the runner's share applies
 * only to the delivery fee — the two never cross. The commission is rounded
 * first, so the restaurant share (subtotal minus commission) is exact and
 * never touched by rounding. The runner share is rounded from the delivery
 * fee; the platform absorbs whatever remainder that rounding leaves, so all
 * three shares always sum to exactly foodSubtotalKobo + deliveryFeeKobo (no
 * kobo lost or invented).
 */
export function computeCommissionShares(
  foodSubtotalKobo: number,
  deliveryFeeKobo: number,
  rates: CommissionRates,
): CommissionShares {
  const commission = Math.round(foodSubtotalKobo * rates.restaurantCommissionRate);
  const runnerShare = Math.round(deliveryFeeKobo * rates.runnerDeliveryFeeShare);
  const restaurantShare = foodSubtotalKobo - commission;
  const platformFee = commission + (deliveryFeeKobo - runnerShare);
  const totalAmount = foodSubtotalKobo + deliveryFeeKobo;

  return { platformFee, restaurantShare, runnerShare, totalAmount };
}
