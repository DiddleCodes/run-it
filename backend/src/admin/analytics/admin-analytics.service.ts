import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AnalyticsOrder, buildMenuAnalytics } from './menu-analytics';
import { MenuAnalyticsQueryDto } from './menu-analytics-query.dto';

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_WINDOW_DAYS = 30;

@Injectable()
export class AdminAnalyticsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Which dishes, at which restaurants, earn the most — over [from, to] by
   * delivery time, compared with the same-length period just before it.
   */
  async menu(query: MenuAnalyticsQueryDto) {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - DEFAULT_WINDOW_DAYS * DAY_MS);
    const length = Math.max(to.getTime() - from.getTime(), 0);
    const previousFrom = new Date(from.getTime() - length);
    const vendorFilter = query.vendorId ? { vendorId: query.vendorId } : {};

    // Earnings rule: delivered, and the customer wasn't refunded.
    const earning = { ...vendorFilter, status: 'delivered' as const, escrow: { status: { not: 'refunded' as const } } };
    const select = {
      vendorId: true,
      vendor: { select: { businessName: true } },
      escrow: { select: { restaurantShare: true } },
      items: { select: { menuItemId: true, nameSnapshot: true, priceSnapshot: true, quantity: true } },
    } as const;

    const [current, previous, menuItems, restaurantOptions] = await Promise.all([
      this.prisma.order.findMany({ where: { ...earning, deliveredAt: { gte: from, lte: to } }, select }),
      this.prisma.order.findMany({ where: { ...earning, deliveredAt: { gte: previousFrom, lt: from } }, select }),
      this.prisma.menuItem.findMany({
        where: { ...vendorFilter, vendor: { status: 'active' } },
        select: { id: true, vendorId: true, name: true, isAvailable: true },
      }),
      this.prisma.vendor.findMany({ select: { id: true, businessName: true }, orderBy: { businessName: 'asc' } }),
    ]);

    const toOrder = (o: (typeof current)[number]): AnalyticsOrder => ({
      vendorId: o.vendorId,
      restaurantName: o.vendor.businessName,
      restaurantShare: o.escrow?.restaurantShare ?? 0,
      items: o.items.map((i) => ({ menuItemId: i.menuItemId, name: i.nameSnapshot, price: i.priceSnapshot, quantity: i.quantity })),
    });

    return {
      from,
      to,
      previousFrom,
      vendorId: query.vendorId ?? null,
      restaurantOptions: restaurantOptions.map((v) => ({ id: v.id, name: v.businessName })),
      ...buildMenuAnalytics({
        current: current.map(toOrder),
        previous: previous.map(toOrder),
        menuItems,
        periodDays: Math.max(Math.round(length / DAY_MS), 1),
      }),
    };
  }
}
