import { computeCommissionShares, computeServiceFeeKobo } from '../src/order-escrow/commission.util';

const RATES = {
  restaurantCommissionRate: 0.15,
  restaurantPlatformFeeKobo: 20_000,
  runnerDeliveryPayKobo: 20_000,
};

describe('computeCommissionShares', () => {
  it('applies commission plus the flat platform fee to the restaurant, and pays the runner a flat amount', () => {
    const shares = computeCommissionShares(100_000, 50_000, 15_000, RATES);

    // 15% of 100,000 food subtotal = 15,000 commission.
    expect(shares.restaurantCommission).toBe(15_000);
    // Restaurant keeps the food subtotal minus commission minus the flat
    // ₦200 platform fee — the delivery fee and service fee never touch this.
    expect(shares.restaurantShare).toBe(100_000 - 15_000 - 20_000);
    // Runner is paid the flat amount regardless of the delivery fee charged.
    expect(shares.runnerShare).toBe(20_000);
    expect(shares.totalAmount).toBe(100_000 + 50_000 + 15_000);
    // Platform keeps everything else: commission + its flat fee + 100% of
    // delivery fee + 100% of service fee, minus what it pays the runner.
    expect(shares.platformFee).toBe(shares.totalAmount - shares.restaurantShare - shares.runnerShare);
    expect(shares.platformFee + shares.restaurantShare + shares.runnerShare).toBe(shares.totalAmount);
  });

  it('never lets rounding lose or invent a kobo, even on odd amounts', () => {
    const shares = computeCommissionShares(333, 111, 7, {
      restaurantCommissionRate: 0.3333,
      restaurantPlatformFeeKobo: 20_000,
      runnerDeliveryPayKobo: 20_000,
    });

    expect(shares.platformFee + shares.restaurantShare + shares.runnerShare).toBe(shares.totalAmount);
    expect(shares.totalAmount).toBe(333 + 111 + 7);
  });

  it('applies a zero delivery fee and zero service fee cleanly', () => {
    const shares = computeCommissionShares(100_000, 0, 0, RATES);

    expect(shares.runnerShare).toBe(20_000);
    expect(shares.restaurantShare).toBe(100_000 - 15_000 - 20_000);
    expect(shares.totalAmount).toBe(100_000);
    expect(shares.platformFee + shares.restaurantShare + shares.runnerShare).toBe(shares.totalAmount);
  });

  it('surfaces the raw inputs behind restaurantShare for an auditable breakdown', () => {
    const shares = computeCommissionShares(100_000, 50_000, 15_000, RATES);

    expect(shares.foodSubtotal).toBe(100_000);
    expect(shares.restaurantCommission).toBe(15_000);
    expect(shares.restaurantPlatformFee).toBe(20_000);
    expect(shares.foodSubtotal - shares.restaurantCommission - shares.restaurantPlatformFee).toBe(
      shares.restaurantShare,
    );
  });
});

describe('computeServiceFeeKobo (Task 70)', () => {
  it.each([
    [100_000, 5_000], // ₦1,000 -> ₦50
    [123_400, 6_200], // ₦1,234 -> ₦61.70 -> ₦62
    [123_000, 6_200], // ₦1,230 -> ₦61.50 -> ₦62 (half rounds up)
    [122_900, 6_100], // ₦1,229 -> ₦61.45 -> ₦61
    [1_000, 100], // ₦10 -> ₦0.50 -> ₦1
    [900, 0], // ₦9 -> ₦0.45 -> ₦0
    [0, 0],
  ])('5%% of %i kobo is %i kobo, to the nearest whole naira', (subtotal, expected) => {
    expect(computeServiceFeeKobo(subtotal, 0.05)).toBe(expected);
  });

  it('is always a whole number of naira', () => {
    for (let subtotal = 0; subtotal < 500_000; subtotal += 1_337) {
      expect(computeServiceFeeKobo(subtotal, 0.05) % 100).toBe(0);
    }
  });
});

