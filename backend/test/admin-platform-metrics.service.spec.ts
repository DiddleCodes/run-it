import { AdminPlatformMetricsService } from '../src/admin/platform-metrics/admin-platform-metrics.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const service = new AdminPlatformMetricsService(prisma as any);
  return { service, prisma };
}

describe('AdminPlatformMetricsService.metrics', () => {
  it('computes GMV, order volume, active vendors, active runners, and take rate from seeded aggregates', async () => {
    const { service, prisma } = makeService();
    prisma.order.count.mockResolvedValue(12);
    prisma.order.aggregate.mockResolvedValue({ _sum: { totalAmount: 600_000 } });
    prisma.vendor.count.mockResolvedValue(4);
    prisma.order.groupBy.mockResolvedValue([{ runnerUserId: 'runner-1' }, { runnerUserId: 'runner-2' }]);
    prisma.orderEscrow.aggregate.mockResolvedValue({ _sum: { platformFee: 90_000 } });
    prisma.order.findMany.mockResolvedValue([
      { totalAmount: 400_000, vendor: { category: 'Nigerian' } },
      { totalAmount: 200_000, vendor: { category: 'Drinks' } },
    ]);

    const result = await service.metrics({});

    expect(result.gmv).toBe(600_000);
    expect(result.orderVolume).toBe(12);
    expect(result.activeVendors).toBe(4);
    expect(result.activeRunners).toBe(2);
    expect(result.platformRevenue).toBe(90_000);
    expect(result.takeRatePct).toBeCloseTo(15, 5);
    expect(result.categoryBreakdown).toEqual([
      { category: 'Nigerian', gmv: 400_000 },
      { category: 'Drinks', gmv: 200_000 },
    ]);
  });

  it('excludes cancelled orders from GMV/volume, same convention as per-vendor metrics', async () => {
    const { service, prisma } = makeService();
    prisma.order.count.mockResolvedValue(0);
    prisma.order.aggregate.mockResolvedValue({ _sum: { totalAmount: 0 } });

    await service.metrics({});

    expect(prisma.order.count).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ status: { not: 'cancelled' } }) }),
    );
  });

  it('defaults to the last 30 days when no date range is given', async () => {
    const { service } = makeService();

    const before = Date.now();
    const result = await service.metrics({});
    const spanMs = result.to.getTime() - result.from.getTime();

    expect(spanMs).toBeCloseTo(30 * 24 * 60 * 60 * 1000, -3);
    expect(result.to.getTime()).toBeGreaterThanOrEqual(before);
  });

  it('reports a zero take rate (not NaN/Infinity) when GMV is zero', async () => {
    const { service, prisma } = makeService();
    prisma.order.aggregate.mockResolvedValue({ _sum: { totalAmount: 0 } });
    prisma.orderEscrow.aggregate.mockResolvedValue({ _sum: { platformFee: 0 } });

    const result = await service.metrics({});

    expect(result.takeRatePct).toBe(0);
  });
});
