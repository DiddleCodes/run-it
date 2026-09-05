export interface CommissionRates {
  // 0-1, applied to the food subtotal (items + packaging) only — never the
  // delivery fee or the service fee.
  restaurantCommissionRate: number;
  // Kobo, flat. Task 45: a second, additive deduction from the
  // restaurant's payout — on top of, not instead of, the percentage
  // commission above.
  restaurantPlatformFeeKobo: number;
  // Kobo, flat. Task 45: the runner's pay is now a fixed amount per
  // delivery, independent of the delivery fee the student paid — the
  // delivery fee is 100% platform revenue now.
  runnerDeliveryPayKobo: number;
}

export interface CommissionShares {
  platformFee: number;
  restaurantShare: number;
  runnerShare: number;
  totalAmount: number;
  // Task 45: the raw inputs behind restaurantShare, surfaced so callers can
  // persist an auditable breakdown rather than just the net figure.
  foodSubtotal: number;
  restaurantCommission: number;
  restaurantPlatformFee: number;
}

/**
 * Splits a food subtotal, a delivery fee, and a service fee (all integer
 * kobo) into platform/restaurant/runner shares.
 *
 * Task 45's flat-fee model: the delivery fee and the service fee are both
 * 100% platform revenue — neither is commissionable, and neither funds the
 * runner's pay directly any more. The restaurant's payout is the food
 * subtotal minus a percentage commission minus a flat platform fee; the
 * runner's pay is a flat amount per delivery. The platform's cut is
 * whatever's left once those two payouts are subtracted from the total
 * charged — computed as a remainder, not summed from its own parts, so the
 * three shares always sum to exactly totalAmount (no kobo lost or
 * invented), mirroring this function's pre-Task-45 invariant.
 */
export function computeCommissionShares(
  foodSubtotalKobo: number,
  deliveryFeeKobo: number,
  serviceFeeKobo: number,
  rates: CommissionRates,
): CommissionShares {
  const restaurantCommission = Math.round(foodSubtotalKobo * rates.restaurantCommissionRate);
  const restaurantShare = foodSubtotalKobo - restaurantCommission - rates.restaurantPlatformFeeKobo;
  const runnerShare = rates.runnerDeliveryPayKobo;
  const totalAmount = foodSubtotalKobo + deliveryFeeKobo + serviceFeeKobo;
  const platformFee = totalAmount - restaurantShare - runnerShare;

  return {
    platformFee,
    restaurantShare,
    runnerShare,
    totalAmount,
    foodSubtotal: foodSubtotalKobo,
    restaurantCommission,
    restaurantPlatformFee: rates.restaurantPlatformFeeKobo,
  };
}
