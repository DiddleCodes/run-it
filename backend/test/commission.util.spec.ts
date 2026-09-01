import { computeCommissionShares } from '../src/order-escrow/commission.util';

describe('computeCommissionShares', () => {
  it('applies commission to the food subtotal only and splits the delivery fee between runner and platform', () => {
    const shares = computeCommissionShares(10_000, 350, {
      restaurantCommissionRate: 0.15,
      runnerDeliveryFeeShare: 0.85,
    });

    // 15% of 10,000 food subtotal = 1,500 commission.
    expect(shares.restaurantShare).toBe(8_500);
    // 85% of 350 delivery fee = 297.5 -> rounds to 298.
    expect(shares.runnerShare).toBe(298);
    // Platform keeps the commission plus whatever's left of the delivery fee.
    expect(shares.platformFee).toBe(1_500 + (350 - 298));
    expect(shares.totalAmount).toBe(10_350);
    expect(shares.platformFee + shares.restaurantShare + shares.runnerShare).toBe(shares.totalAmount);
  });

  it('never lets rounding lose or invent a kobo, even on odd amounts', () => {
    const shares = computeCommissionShares(333, 111, {
      restaurantCommissionRate: 0.3333,
      runnerDeliveryFeeShare: 0.6667,
    });

    expect(shares.platformFee + shares.restaurantShare + shares.runnerShare).toBe(shares.totalAmount);
    expect(shares.totalAmount).toBe(444);
  });

  it('applies a zero delivery fee cleanly (no runner share, no platform cut of it)', () => {
    const shares = computeCommissionShares(10_000, 0, {
      restaurantCommissionRate: 0.15,
      runnerDeliveryFeeShare: 0.85,
    });

    expect(shares.runnerShare).toBe(0);
    expect(shares.platformFee).toBe(1_500);
    expect(shares.restaurantShare).toBe(8_500);
    expect(shares.totalAmount).toBe(10_000);
  });
});
