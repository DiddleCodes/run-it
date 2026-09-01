import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { MetricsQueryDto } from '../../vendors/dto/metrics-query.dto';

const DEFAULT_METRICS_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

@Injectable()
export class AdminPlatformMetricsService {
  constructor(private readonly prisma: PrismaService) {}

  // Platform-wide, so — unlike the per-vendor metrics endpoint's
  // fetch-then-reduce-in-JS (fine at one vendor's order volume) — this
  // deliberately uses Prisma aggregate/count/groupBy: a genuinely
  // different query shape (every vendor's orders, not one), so the
  // deviation from that established pattern is intentional, not drift.
  async metrics(query: MetricsQueryDto) {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - DEFAULT_METRICS_WINDOW_MS);

    // Cancelled orders are excluded: no money ultimately changed hands,
    // same convention as the per-vendor metrics endpoint.
    const orderWhere = { createdAt: { gte: from, lte: to }, status: { not: 'cancelled' as const } };

    const [orderCount, revenueAgg, activeVendors, runnerGroups, escrowAgg, ordersWithCategory] = await Promise.all([
      this.prisma.order.count({ where: orderWhere }),
      this.prisma.order.aggregate({ where: orderWhere, _sum: { totalAmount: true } }),
      this.prisma.vendor.count({ where: { status: 'active' } }),
      this.prisma.order.groupBy({ by: ['runnerUserId'], where: { ...orderWhere, runnerUserId: { not: null } } }),
      this.prisma.orderEscrow.aggregate({ where: { createdAt: { gte: from, lte: to } }, _sum: { platformFee: true } }),
      // groupBy can't reach across the Order -> Vendor relation to group
      // by Vendor.category directly, so the one real per-category
      // breakdown the data supports is built here instead: fetch each
      // order's amount + its vendor's category, reduce in JS. Not a
      // fabricated time series — the same "only build what's real"
      // discipline as the per-vendor metrics endpoint.
      this.prisma.order.findMany({ where: orderWhere, select: { totalAmount: true, vendor: { select: { category: true } } } }),
    ]);

    const gmv = revenueAgg._sum.totalAmount ?? 0;
    const platformRevenue = escrowAgg._sum.platformFee ?? 0;
    const takeRatePct = gmv > 0 ? (platformRevenue / gmv) * 100 : 0;

    const categoryTotals = new Map<string, number>();
    for (const order of ordersWithCategory) {
      const category = order.vendor.category;
      categoryTotals.set(category, (categoryTotals.get(category) ?? 0) + order.totalAmount);
    }
    const categoryBreakdown = [...categoryTotals.entries()]
      .map(([category, gmv]) => ({ category, gmv }))
      .sort((a, b) => b.gmv - a.gmv);

    return {
      from,
      to,
      gmv,
      orderVolume: orderCount,
      activeVendors,
      activeRunners: runnerGroups.length,
      platformRevenue,
      takeRatePct,
      categoryBreakdown,
    };
  }
}
