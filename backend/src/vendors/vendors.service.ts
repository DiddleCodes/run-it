import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { MenuItem, OrderStatus } from '@prisma/client';
import { CampusService } from '../campus/campus.service';
import { MatchingService } from '../matching/matching.service';
import { NotificationsEmitterService } from '../notifications/notifications-emitter.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreateMenuItemDto } from './dto/create-menu-item.dto';
import { DEFAULT_PAGE_SIZE, ListOrdersQueryDto, MAX_PAGE_SIZE } from './dto/list-orders-query.dto';
import {
  DEFAULT_PAGE_SIZE as DEFAULT_VENDOR_PAGE_SIZE,
  ListVendorsQueryDto,
  MAX_PAGE_SIZE as MAX_VENDOR_PAGE_SIZE,
} from './dto/list-vendors-query.dto';
import { MetricsQueryDto } from './dto/metrics-query.dto';
import { UpdateMenuItemDto } from './dto/update-menu-item.dto';
import { UpdateOrderStatusDto, VendorDrivenStatus } from './dto/update-order-status.dto';
import { UpsertVendorDto } from './dto/upsert-vendor.dto';

const DEFAULT_METRICS_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

// The live kitchen queue — what `listIncomingOrders` returns when the
// caller doesn't ask for a specific status. Deliberately excludes
// `delivered`/`cancelled`: those are done, not incoming.
const ACTIVE_ORDER_STATUSES: OrderStatus[] = ['placed', 'preparing', 'ready_for_pickup', 'picked_up'];

// Task 12: forward-only, exactly these two vendor-triggered steps — every
// other transition belongs to escrow hold/refund or runner verification
// (Task 11), never to this endpoint.
const REQUIRED_CURRENT_STATUS: Record<VendorDrivenStatus, OrderStatus> = {
  preparing: 'placed',
  ready_for_pickup: 'preparing',
};

@Injectable()
export class VendorsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsEmitterService,
    private readonly matching: MatchingService,
    private readonly campus: CampusService,
  ) {}

  // Task 13c: replaces the Task 12 auto-approve stopgap this comment used
  // to document. New submissions go into the admin review queue as
  // `pending` rather than the schema's `active` default — see
  // admin/vendor-review for the approve/reject endpoints. Editing an
  // already-reviewed vendor's profile never touches status, EXCEPT a
  // `rejected` vendor resubmitting: that's the only way back into the
  // queue, so it flips to `pending` and clears the prior rejectionReason.
  async upsertMyVendor(userId: string, dto: UpsertVendorDto) {
    const category = await this.resolveCategoryLabel(dto.category);
    if (dto.requestedCampusId) await this.campus.requireById(dto.requestedCampusId);
    const data = { ...dto, category };
    const existing = await this.prisma.vendor.findUnique({ where: { userId } });

    return this.prisma.vendor.upsert({
      where: { userId },
      create: { userId, ...data, status: 'pending' },
      update:
        existing?.status === 'rejected' ? { ...data, status: 'pending', rejectionReason: null } : { ...data },
    });
  }

  // A controlled vocabulary so "Nigerian Food"/"nigerian food"/"Naija
  // Dishes" can never coexist as separate, un-mergeable category chips.
  // Matches case-insensitively against either the stable slug or the
  // display label, but always persists the canonical label — so even a
  // slightly different casing self-heals to one consistent value.
  async listCategories() {
    return this.prisma.vendorCategory.findMany({ orderBy: { label: 'asc' } });
  }

  private async resolveCategoryLabel(input: string): Promise<string> {
    const categories = await this.prisma.vendorCategory.findMany();
    const match = categories.find(
      (c) => c.label.toLowerCase() === input.toLowerCase() || c.slug.toLowerCase() === input.toLowerCase(),
    );
    if (!match) {
      throw new BadRequestException(
        `Unknown vendor category "${input}". Valid categories: ${categories.map((c) => c.label).join(', ')}`,
      );
    }
    return match.label;
  }

  // The Restaurant Dashboard's own Profile tab needs to read back what it
  // already told the backend (to prefill an edit form) — every other
  // vendor-scoped route so far only ever *wrote* through `userId`, never
  // read the resulting row back.
  async getMyVendor(userId: string) {
    return this.getOwnVendorOrThrow(userId);
  }

  // Task 14/26: the Home screen's search + category chips, now scoped to
  // the caller's own campus (see VendorsController.listVendors — a null
  // campusId means "show nothing" rather than "show everything", since an
  // unscoped result would leak other campuses' restaurants to whatever
  // account type/edge case reaches this with no campus of its own). Only
  // ever surfaces `active` vendors — a restaurant that's gone `inactive`
  // shouldn't show up for a student browsing campus, even though its
  // historical orders/menu rows still exist.
  async listVendors(query: ListVendorsQueryDto, campusId: string | null) {
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_VENDOR_PAGE_SIZE, MAX_VENDOR_PAGE_SIZE);
    const search = query.search?.trim();

    if (!campusId) {
      return { items: [], total: 0, page, limit };
    }

    const where = {
      status: 'active' as const,
      user: { campusId },
      ...(query.category ? { category: { equals: query.category, mode: 'insensitive' as const } } : {}),
      ...(search
        ? {
            OR: [
              { businessName: { contains: search, mode: 'insensitive' as const } },
              { description: { contains: search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.vendor.findMany({
        where,
        orderBy: { businessName: 'asc' },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          businessName: true,
          category: true,
          description: true,
          logoUrl: true,
          // Task 48: real, student-facing restaurant rating — shown
          // wherever a student browses vendors, not fabricated.
          averageRating: true,
          ratingCount: true,
        },
      }),
      this.prisma.vendor.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  // Task 13c: only an `active` (admin-approved) vendor's menu is orderable —
  // a pending/rejected vendor's menu was previously reachable directly by
  // id even though listVendors already filtered to active only. 404 (not a
  // distinct "not approved" error) so a pending vendor's existence isn't
  // leaked to a student who guesses/bookmarks its id.
  async getPublicMenu(vendorId: string) {
    const vendor = await this.prisma.vendor.findUnique({ where: { id: vendorId, status: 'active' } });
    if (!vendor) throw new NotFoundException('Vendor not found');

    const items = await this.prisma.menuItem.findMany({
      where: { vendorId },
      orderBy: [{ category: 'asc' }, { name: 'asc' }],
    });

    return { vendor, items };
  }

  async createMenuItem(userId: string, dto: CreateMenuItemDto) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    return this.prisma.menuItem.create({ data: { vendorId: vendor.id, ...dto } });
  }

  async updateMenuItem(userId: string, itemId: string, dto: UpdateMenuItemDto) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    await this.assertOwnsMenuItem(vendor.id, itemId);
    return this.prisma.menuItem.update({ where: { id: itemId }, data: dto });
  }

  async deleteMenuItem(userId: string, itemId: string) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    await this.assertOwnsMenuItem(vendor.id, itemId);
    await this.prisma.menuItem.delete({ where: { id: itemId } });
    return { deleted: true };
  }

  async setAvailability(userId: string, itemId: string, isAvailable: boolean) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    await this.assertOwnsMenuItem(vendor.id, itemId);
    return this.prisma.menuItem.update({ where: { id: itemId }, data: { isAvailable } });
  }

  // Task 11 built this for exactly one thing (orders awaiting pickup, with
  // their pickup code) — Task 12's Restaurant Dashboard Orders tab extends
  // the SAME endpoint into the general paginated/filterable order listing,
  // rather than standing up a second, overlapping GET. No `status` filter
  // means "the live kitchen queue" (ACTIVE_ORDER_STATUSES); pass one
  // explicitly (e.g. `delivered`) to see history instead.
  //
  // Explicit `select` (not `include`) so this never leaks the order's
  // deliveryPin or studentUserId — the vendor is not a party to those. The
  // pickup code is included regardless of status: it's only actually
  // meaningful once `ready_for_pickup`, but harmless to show earlier too
  // (Flutter only surfaces it once the status makes sense to a kitchen).
  async listIncomingOrders(userId: string, query: ListOrdersQueryDto) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    const where = {
      vendorId: vendor.id,
      status: query.status ?? { in: ACTIVE_ORDER_STATUSES },
    };

    const [items, total] = await Promise.all([
      this.prisma.order.findMany({
        where,
        orderBy: { createdAt: 'asc' },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          status: true,
          pickupCode: true,
          totalAmount: true,
          deliveryLocationLabel: true,
          note: true,
          createdAt: true,
          items: {
            select: { id: true, nameSnapshot: true, quantity: true, priceSnapshot: true },
          },
          // Task 45: the restaurant's own payout breakdown — a plainly
          // labeled itemization (food subtotal, minus commission, minus the
          // flat platform fee), never a disguised deduction. Only the
          // restaurant's own three inputs/output are selected here, not
          // platformFee/runnerShare — the platform's overall take isn't the
          // restaurant's business.
          escrow: {
            select: {
              foodSubtotal: true,
              restaurantCommission: true,
              restaurantPlatformFee: true,
              restaurantShare: true,
            },
          },
        },
      }),
      this.prisma.order.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  // Forward-only: `placed -> preparing -> ready_for_pickup`, nothing else.
  // Ownership is enforced the same way menu-item mutations are — the order
  // must belong to the calling vendor's own vendor row, not just any order.
  async advanceOrderStatus(userId: string, orderId: string, dto: UpdateOrderStatusDto) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (order.vendorId !== vendor.id) throw new ForbiddenException('You do not own this order');

    const requiredCurrentStatus = REQUIRED_CURRENT_STATUS[dto.status];
    if (order.status !== requiredCurrentStatus) {
      throw new ConflictException(
        `Cannot move order ${orderId} to "${dto.status}" — it is currently "${order.status}", not "${requiredCurrentStatus}"`,
      );
    }

    const updated = await this.prisma.order.update({
      where: { id: orderId },
      // Task 46: "preparing" is the vendor's acceptance moment — the one
      // real event this transition set covers (ready_for_pickup has no
      // timestamp of its own, per this task's exact four fields).
      data: { status: dto.status, ...(dto.status === 'preparing' ? { acceptedAt: new Date() } : {}) },
    });

    // "preparing" is the vendor's acceptance of the order — the student-
    // facing "order accepted" moment. "ready_for_pickup" has no event of
    // its own in this task's scope (see the brief's exact six event types).
    if (dto.status === 'preparing') {
      this.notifications.emit({
        type: 'order_accepted',
        recipientUserId: order.studentUserId,
        title: 'Order accepted',
        body: `${vendor.businessName} has accepted your order and started preparing it.`,
        data: { orderId },
      });

      // Task 21a: this is the "restaurant accepted, now it genuinely needs
      // a runner" moment the matching flow broadcasts on — not order
      // placement, since a restaurant hasn't even seen the order yet at
      // that point. Only fires for orders held with no runner attached;
      // the not-yet-updated Flutter client still resolves one up front
      // (Task 21b), and there is nothing to broadcast or claim for those.
      if (!updated.runnerUserId) {
        await this.matching.broadcastNewJob(orderId);
      }
    }

    return updated;
  }

  async metrics(userId: string, query: MetricsQueryDto) {
    const vendor = await this.getOwnVendorOrThrow(userId);
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - DEFAULT_METRICS_WINDOW_MS);

    // Cancelled orders are excluded: no money ultimately changed hands for
    // them, so counting their items would overstate real sales.
    const orders = await this.prisma.order.findMany({
      where: {
        vendorId: vendor.id,
        createdAt: { gte: from, lte: to },
        status: { not: 'cancelled' },
      },
      include: { items: true },
    });

    const totalRevenue = orders.reduce((sum, order) => sum + order.totalAmount, 0);

    const itemStats = new Map<string, { menuItemId: string | null; name: string; count: number; revenue: number }>();
    for (const order of orders) {
      for (const item of order.items) {
        const key = item.menuItemId ?? `unlinked:${item.nameSnapshot}`;
        const existing = itemStats.get(key) ?? {
          menuItemId: item.menuItemId,
          name: item.nameSnapshot,
          count: 0,
          revenue: 0,
        };
        existing.count += item.quantity;
        existing.revenue += item.priceSnapshot * item.quantity;
        itemStats.set(key, existing);
      }
    }

    const mostOrderedItems = [...itemStats.values()].sort((a, b) => b.count - a.count);

    return {
      from,
      to,
      totalOrders: orders.length,
      totalRevenue,
      mostOrderedItems,
    };
  }

  private async getOwnVendorOrThrow(userId: string) {
    const vendor = await this.prisma.vendor.findUnique({ where: { userId } });
    if (!vendor) throw new NotFoundException('Create your vendor profile first via POST /vendors/me');
    return vendor;
  }

  private async assertOwnsMenuItem(vendorId: string, itemId: string): Promise<MenuItem> {
    const item = await this.prisma.menuItem.findUnique({ where: { id: itemId } });
    if (!item) throw new NotFoundException('Menu item not found');
    if (item.vendorId !== vendorId) throw new ForbiddenException('You do not own this menu item');
    return item;
  }
}
