import { classifyPayout, EarningsRow, toLine, totalEarnings } from '../src/vendors/earnings.util';
import { VendorsService } from '../src/vendors/vendors.service';
import { createConfigMock, createNotificationsEmitterMock, createPrismaMock } from './support/mocks';

const row = (over: Partial<EarningsRow> = {}): EarningsRow => ({
  orderId: 'order-1',
  pickupCode: '5319',
  orderStatus: 'delivered',
  deliveredAt: new Date('2026-10-07T12:00:00Z'),
  escrowStatus: 'released',
  restaurantTransferStatus: 'success',
  foodSubtotal: 80_000,
  restaurantCommission: 12_000,
  restaurantPlatformFee: 20_000,
  restaurantShare: 48_000,
  ...over,
});

describe('classifyPayout', () => {
  it('a delivered order is settled once the transfer succeeded, failed if it failed, otherwise pending', () => {
    expect(classifyPayout(row())).toBe('settled');
    expect(classifyPayout(row({ restaurantTransferStatus: 'failed' }))).toBe('failed');
    expect(classifyPayout(row({ restaurantTransferStatus: 'pending' }))).toBe('pending');
    // Release hasn't run / couldn't initiate yet: still owed, so pending.
    expect(classifyPayout(row({ escrowStatus: 'held', restaurantTransferStatus: 'not_applicable' }))).toBe('pending');
  });

  it('a cancelled order or a refunded escrow is never earnings — not pending, not settled', () => {
    expect(classifyPayout(row({ orderStatus: 'cancelled', escrowStatus: 'refunded' }))).toBeNull();
    expect(classifyPayout(row({ escrowStatus: 'refunded', restaurantTransferStatus: 'not_applicable' }))).toBeNull();
    // Even a refund that somehow sits next to a "success" leg doesn't count.
    expect(classifyPayout(row({ escrowStatus: 'refunded' }))).toBeNull();
    expect(classifyPayout(row({ orderStatus: 'cancelled' }))).toBeNull();
  });

  it('an order still on its way earns nothing yet', () => {
    for (const orderStatus of ['placed', 'preparing', 'ready_for_pickup', 'picked_up'] as const) {
      expect(classifyPayout(row({ orderStatus, escrowStatus: 'held', restaurantTransferStatus: 'not_applicable' }))).toBeNull();
    }
  });
});

describe('totalEarnings', () => {
  it('adds payouts (the restaurant share) by state and skips anything cancelled or refunded', () => {
    const totals = totalEarnings([
      row({ restaurantShare: 48_000 }),
      row({ restaurantShare: 122_825 }),
      row({ restaurantTransferStatus: 'pending', restaurantShare: 30_000 }),
      row({ escrowStatus: 'held', restaurantTransferStatus: 'not_applicable', restaurantShare: 10_050 }),
      row({ restaurantTransferStatus: 'failed', restaurantShare: 99_900 }),
      row({ orderStatus: 'cancelled', escrowStatus: 'refunded', restaurantShare: 1_000_000 }),
      row({ escrowStatus: 'refunded', restaurantTransferStatus: 'pending', restaurantShare: 2_000_000 }),
    ]);
    expect(totals).toEqual({
      settledKobo: 170_825,
      settledCount: 2,
      pendingKobo: 40_050,
      pendingCount: 2,
      failedKobo: 99_900,
      failedCount: 1,
    });
  });

  it('is all zeros for a new restaurant', () => {
    expect(totalEarnings([])).toEqual({ settledKobo: 0, settledCount: 0, pendingKobo: 0, pendingCount: 0, failedKobo: 0, failedCount: 0 });
  });
});

describe('toLine', () => {
  it("Bridgit's commission is the commission plus the platform fee, so food − commission = payout", () => {
    const line = toLine(row())!;
    expect(line).toMatchObject({ foodSubtotalKobo: 80_000, commissionKobo: 32_000, payoutKobo: 48_000, payoutStatus: 'settled' });
    expect(line.foodSubtotalKobo - line.commissionKobo).toBe(line.payoutKobo);
  });
});

describe('VendorsService.earnings', () => {
  function makeService() {
    const prisma = createPrismaMock();
    const service = new VendorsService(
      prisma as any,
      createNotificationsEmitterMock() as any,
      { broadcastNewJob: jest.fn() } as any,
      { requireById: jest.fn() } as any,
      createConfigMock({}) as any,
      { refund: jest.fn() } as any,
    );
    return { service, prisma };
  }

  const dbOrder = (over: Record<string, unknown> = {}, escrow: Record<string, unknown> = {}) => ({
    id: 'order-1',
    pickupCode: '5319',
    status: 'delivered',
    deliveredAt: new Date('2026-10-07T12:00:00Z'),
    escrow: {
      status: 'released',
      restaurantTransferStatus: 'success',
      foodSubtotal: 80_000,
      restaurantCommission: 12_000,
      restaurantPlatformFee: 20_000,
      restaurantShare: 48_000,
      ...escrow,
    },
    ...over,
  });

  it("only ever reads this restaurant's own delivered, unrefunded orders", async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', userId: 'rest-user-1' });
    prisma.order.findMany.mockResolvedValue([]);

    await service.earnings('rest-user-1', { from: '2026-10-01T00:00:00Z', to: '2026-10-08T00:00:00Z' });

    expect(prisma.vendor.findUnique).toHaveBeenCalledWith({ where: { userId: 'rest-user-1' } });
    for (const [args] of prisma.order.findMany.mock.calls) {
      expect(args.where).toMatchObject({ vendorId: 'vendor-1', status: 'delivered', escrow: { status: { not: 'refunded' } } });
    }
  });

  it('settled covers the range; pending and failed are everything outstanding now', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', userId: 'rest-user-1' });
    prisma.order.findMany
      .mockResolvedValueOnce([
        dbOrder(),
        dbOrder({ id: 'order-2', pickupCode: '4410' }, { restaurantTransferStatus: 'pending', restaurantShare: 30_000 }),
      ])
      .mockResolvedValueOnce([
        dbOrder({ id: 'order-2' }, { restaurantTransferStatus: 'pending', restaurantShare: 30_000 }),
        dbOrder({ id: 'old-failed', deliveredAt: new Date('2026-08-01T12:00:00Z') }, { restaurantTransferStatus: 'failed', restaurantShare: 99_900 }),
      ]);

    const result = await service.earnings('rest-user-1', {});

    expect(result.summary).toEqual({
      settledKobo: 48_000,
      settledCount: 1,
      pendingKobo: 30_000,
      pendingCount: 1,
      failedKobo: 99_900,
      failedCount: 1,
    });
    expect(result.items.map((i) => [i.pickupCode, i.payoutStatus])).toEqual([
      ['5319', 'settled'],
      ['4410', 'pending'],
    ]);
  });

  it('a new restaurant gets zeros and an empty list', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', userId: 'rest-user-1' });
    prisma.order.findMany.mockResolvedValue([]);

    const result = await service.earnings('rest-user-1', {});

    expect(result.items).toEqual([]);
    expect(result.summary.settledKobo + result.summary.pendingKobo + result.summary.failedKobo).toBe(0);
  });
});
