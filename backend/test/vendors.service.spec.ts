import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { VendorsService } from '../src/vendors/vendors.service';
import { createMatchingServiceMock, createNotificationsEmitterMock, createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const notifications = createNotificationsEmitterMock();
  const matching = createMatchingServiceMock();
  const service = new VendorsService(prisma as any, notifications as any, matching as any);
  return { service, prisma, notifications, matching };
}

describe('VendorsService menu ownership enforcement', () => {
  it('rejects updating a menu item that belongs to a different vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.menuItem.findUnique.mockResolvedValue({ id: 'item-1', vendorId: 'vendor-B' });

    await expect(
      service.updateMenuItem('user-A', 'item-1', { name: 'Hijacked name' }),
    ).rejects.toThrow(ForbiddenException);
    expect(prisma.menuItem.update).not.toHaveBeenCalled();
  });

  it('rejects deleting a menu item that belongs to a different vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.menuItem.findUnique.mockResolvedValue({ id: 'item-1', vendorId: 'vendor-B' });

    await expect(service.deleteMenuItem('user-A', 'item-1')).rejects.toThrow(ForbiddenException);
    expect(prisma.menuItem.delete).not.toHaveBeenCalled();
  });

  it('rejects toggling availability on a menu item that belongs to a different vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.menuItem.findUnique.mockResolvedValue({ id: 'item-1', vendorId: 'vendor-B' });

    await expect(service.setAvailability('user-A', 'item-1', false)).rejects.toThrow(ForbiddenException);
    expect(prisma.menuItem.update).not.toHaveBeenCalled();
  });

  it('allows updating a menu item that belongs to the caller\'s own vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.menuItem.findUnique.mockResolvedValue({ id: 'item-1', vendorId: 'vendor-A' });
    prisma.menuItem.update.mockResolvedValue({ id: 'item-1', vendorId: 'vendor-A', name: 'Updated' });

    const result = await service.updateMenuItem('user-A', 'item-1', { name: 'Updated' });

    expect(result.name).toBe('Updated');
    expect(prisma.menuItem.update).toHaveBeenCalledWith({
      where: { id: 'item-1' },
      data: { name: 'Updated' },
    });
  });

  it('requires a vendor profile to exist before creating a menu item', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue(null);

    await expect(
      service.createMenuItem('user-A', { name: 'Jollof', price: 3000, category: 'Mains' }),
    ).rejects.toThrow(NotFoundException);
  });
});

describe('VendorsService.upsertMyVendor', () => {
  const categories = [
    { slug: 'nigerian', label: 'Nigerian' },
    { slug: 'fast-food', label: 'Fast Food' },
  ];

  it('rejects a category that is not in the controlled vocabulary', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);

    await expect(
      service.upsertMyVendor('user-A', { businessName: 'Naija Bites', category: 'Naija Dishes' }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.vendor.upsert).not.toHaveBeenCalled();
  });

  it('accepts a case-insensitive match and persists the canonical label, not the raw input', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);
    prisma.vendor.upsert.mockResolvedValue({ id: 'vendor-1', category: 'Nigerian' });

    await service.upsertMyVendor('user-A', { businessName: 'Naija Bites', category: 'nigerian' });

    // "nigerian" (lowercase, matches the label case-insensitively) should
    // be stored as the canonical "Nigerian", never the raw input casing.
    expect(prisma.vendor.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ category: 'Nigerian' }),
        update: expect.objectContaining({ category: 'Nigerian' }),
      }),
    );
  });

  it('also matches by slug, not just label', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);
    prisma.vendor.upsert.mockResolvedValue({ id: 'vendor-1', category: 'Fast Food' });

    await service.upsertMyVendor('user-A', { businessName: 'Quick Bites', category: 'fast-food' });

    expect(prisma.vendor.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ category: 'Fast Food' }) }),
    );
  });
});

describe('VendorsService.upsertMyVendor — admin review gate', () => {
  const categories = [{ slug: 'nigerian', label: 'Nigerian' }];

  it('defaults a brand-new vendor to pending, not active', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);
    prisma.vendor.findUnique.mockResolvedValue(null);
    prisma.vendor.upsert.mockResolvedValue({ id: 'vendor-1', status: 'pending' });

    await service.upsertMyVendor('user-A', { businessName: 'Naija Bites', category: 'Nigerian' });

    expect(prisma.vendor.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ status: 'pending' }) }),
    );
  });

  it('leaves an already-active vendor untouched on a normal profile edit', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', status: 'active' });
    prisma.vendor.upsert.mockResolvedValue({ id: 'vendor-1', status: 'active' });

    await service.upsertMyVendor('user-A', { businessName: 'Naija Bites', category: 'Nigerian' });

    const call = prisma.vendor.upsert.mock.calls[0][0];
    expect(call.update.status).toBeUndefined();
  });

  it('flips a rejected vendor back to pending and clears the rejection reason on resubmit', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue(categories);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', status: 'rejected' });
    prisma.vendor.upsert.mockResolvedValue({ id: 'vendor-1', status: 'pending' });

    await service.upsertMyVendor('user-A', { businessName: 'Naija Bites', category: 'Nigerian' });

    expect(prisma.vendor.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: expect.objectContaining({ status: 'pending', rejectionReason: null }),
      }),
    );
  });
});

describe('VendorsService.getPublicMenu', () => {
  it('only ever looks up an active vendor by id, and 404s otherwise', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue(null);

    await expect(service.getPublicMenu('vendor-pending')).rejects.toThrow(NotFoundException);
    expect(prisma.vendor.findUnique).toHaveBeenCalledWith({
      where: { id: 'vendor-pending', status: 'active' },
    });
  });
});

describe('VendorsService.listCategories', () => {
  it('returns the controlled vocabulary sorted by label', async () => {
    const { service, prisma } = makeService();
    prisma.vendorCategory.findMany.mockResolvedValue([{ slug: 'nigerian', label: 'Nigerian' }]);

    const result = await service.listCategories();

    expect(prisma.vendorCategory.findMany).toHaveBeenCalledWith({ orderBy: { label: 'asc' } });
    expect(result).toEqual([{ slug: 'nigerian', label: 'Nigerian' }]);
  });
});

describe('VendorsService.listVendors', () => {
  it('only ever queries for active vendors, even with no other filters', async () => {
    const { service, prisma } = makeService();

    await service.listVendors({});

    expect(prisma.vendor.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { status: 'active' } }),
    );
  });

  it('filters by category case-insensitively', async () => {
    const { service, prisma } = makeService();

    await service.listVendors({ category: 'drinks' });

    expect(prisma.vendor.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { status: 'active', category: { equals: 'drinks', mode: 'insensitive' } },
      }),
    );
  });

  it('searches business name and description case-insensitively', async () => {
    const { service, prisma } = makeService();

    await service.listVendors({ search: 'jollof' });

    expect(prisma.vendor.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          status: 'active',
          OR: [
            { businessName: { contains: 'jollof', mode: 'insensitive' } },
            { description: { contains: 'jollof', mode: 'insensitive' } },
          ],
        },
      }),
    );
  });

  it('paginates with a default page size and reports the real total', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findMany.mockResolvedValue([{ id: 'vendor-1' }]);
    prisma.vendor.count.mockResolvedValue(33);

    const result = await service.listVendors({ page: 2, limit: 10 });

    expect(prisma.vendor.findMany).toHaveBeenCalledWith(expect.objectContaining({ skip: 10, take: 10 }));
    expect(result).toEqual({ items: [{ id: 'vendor-1' }], total: 33, page: 2, limit: 10 });
  });
});

describe('VendorsService.metrics', () => {
  it('aggregates total revenue and per-item counts correctly, excluding cancelled orders', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findMany.mockResolvedValue([
      {
        id: 'order-1',
        totalAmount: 5_000,
        items: [
          { menuItemId: 'm1', nameSnapshot: 'Jollof', priceSnapshot: 3_000, quantity: 1 },
          { menuItemId: 'm2', nameSnapshot: 'Zobo', priceSnapshot: 2_000, quantity: 1 },
        ],
      },
      {
        id: 'order-2',
        totalAmount: 3_000,
        items: [{ menuItemId: 'm1', nameSnapshot: 'Jollof', priceSnapshot: 3_000, quantity: 1 }],
      },
    ]);

    const result = await service.metrics('user-A', {});

    expect(prisma.order.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ vendorId: 'vendor-A', status: { not: 'cancelled' } }),
      }),
    );
    expect(result.totalOrders).toBe(2);
    expect(result.totalRevenue).toBe(8_000);

    const jollof = result.mostOrderedItems.find((item) => item.menuItemId === 'm1');
    expect(jollof).toEqual(
      expect.objectContaining({ name: 'Jollof', count: 2, revenue: 6_000 }),
    );
    // Ranked by count, most-ordered first.
    expect(result.mostOrderedItems[0].menuItemId).toBe('m1');
  });

  it('defaults to the last 30 days when no date range is given', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findMany.mockResolvedValue([]);

    const before = Date.now();
    const result = await service.metrics('user-A', {});
    const spanMs = result.to.getTime() - result.from.getTime();

    expect(spanMs).toBeCloseTo(30 * 24 * 60 * 60 * 1000, -3);
    expect(result.to.getTime()).toBeGreaterThanOrEqual(before);
  });
});

describe('VendorsService.listIncomingOrders', () => {
  it('defaults to the live kitchen queue (excludes delivered/cancelled) when no status filter is given', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findMany.mockResolvedValue([]);
    prisma.order.count.mockResolvedValue(0);

    await service.listIncomingOrders('user-A', {});

    expect(prisma.order.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          vendorId: 'vendor-A',
          status: { in: ['placed', 'preparing', 'ready_for_pickup', 'picked_up'] },
        },
      }),
    );
  });

  it('filters to exactly one status when given (e.g. delivered history)', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findMany.mockResolvedValue([]);
    prisma.order.count.mockResolvedValue(0);

    await service.listIncomingOrders('user-A', { status: 'delivered' });

    expect(prisma.order.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { vendorId: 'vendor-A', status: 'delivered' } }),
    );
  });

  it('paginates with a default page size and reports the real total', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findMany.mockResolvedValue([{ id: 'order-1' }]);
    prisma.order.count.mockResolvedValue(47);

    const result = await service.listIncomingOrders('user-A', { page: 2, limit: 10 });

    expect(prisma.order.findMany).toHaveBeenCalledWith(expect.objectContaining({ skip: 10, take: 10 }));
    expect(result).toEqual({ items: [{ id: 'order-1' }], total: 47, page: 2, limit: 10 });
  });
});

describe('VendorsService.advanceOrderStatus', () => {
  it('rejects advancing an order that belongs to a different vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-B', status: 'placed' });

    await expect(
      service.advanceOrderStatus('user-A', 'order-1', { status: 'preparing' }),
    ).rejects.toThrow(ForbiddenException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rejects skipping straight from placed to ready_for_pickup', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'placed' });

    await expect(
      service.advanceOrderStatus('user-A', 'order-1', { status: 'ready_for_pickup' }),
    ).rejects.toThrow(ConflictException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rejects re-applying a transition that already happened (placed -> preparing twice)', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'preparing' });

    await expect(
      service.advanceOrderStatus('user-A', 'order-1', { status: 'preparing' }),
    ).rejects.toThrow(ConflictException);
  });

  it('allows placed -> preparing for the order\'s own vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'placed' });
    prisma.order.update.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'preparing' });

    const result = await service.advanceOrderStatus('user-A', 'order-1', { status: 'preparing' });

    expect(result.status).toBe('preparing');
    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'preparing' },
    });
  });

  it('allows preparing -> ready_for_pickup for the order\'s own vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'preparing' });
    prisma.order.update.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'ready_for_pickup' });

    const result = await service.advanceOrderStatus('user-A', 'order-1', { status: 'ready_for_pickup' });

    expect(result.status).toBe('ready_for_pickup');
  });

  it('rejects when the order does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue(null);

    await expect(
      service.advanceOrderStatus('user-A', 'missing-order', { status: 'preparing' }),
    ).rejects.toThrow(NotFoundException);
  });

  // Task 21a: "preparing" is the restaurant-acceptance moment the matching
  // flow broadcasts on.
  it('broadcasts a new job when accepting (-> preparing) an order held with no runner attached', async () => {
    const { service, prisma, matching } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'placed' });
    prisma.order.update.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'preparing', runnerUserId: null });

    await service.advanceOrderStatus('user-A', 'order-1', { status: 'preparing' });

    expect(matching.broadcastNewJob).toHaveBeenCalledWith('order-1');
  });

  it('does not broadcast when accepting an order that already has a runner attached (pre-21b Flutter client)', async () => {
    const { service, prisma, matching } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'placed' });
    prisma.order.update.mockResolvedValue({
      id: 'order-1',
      vendorId: 'vendor-A',
      status: 'preparing',
      runnerUserId: 'demo-runner-1',
    });

    await service.advanceOrderStatus('user-A', 'order-1', { status: 'preparing' });

    expect(matching.broadcastNewJob).not.toHaveBeenCalled();
  });

  it('does not broadcast for the ready_for_pickup transition', async () => {
    const { service, prisma, matching } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-A' });
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'preparing' });
    prisma.order.update.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-A', status: 'ready_for_pickup', runnerUserId: null });

    await service.advanceOrderStatus('user-A', 'order-1', { status: 'ready_for_pickup' });

    expect(matching.broadcastNewJob).not.toHaveBeenCalled();
  });
});
