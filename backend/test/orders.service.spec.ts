import { BadRequestException, ConflictException, ForbiddenException, HttpException, NotFoundException } from '@nestjs/common';
import { OrdersService } from '../src/orders/orders.service';
import { createNotificationsEmitterMock, createPrismaMock, createRedisMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const redis = createRedisMock();
  const escrow = { release: jest.fn().mockResolvedValue({ id: 'escrow-1', status: 'released' }) };
  const notifications = createNotificationsEmitterMock();
  const service = new OrdersService(prisma as any, escrow as any, redis as any, notifications as any);
  return { service, prisma, redis, escrow, notifications };
}

const baseOrder = {
  id: 'order-1',
  status: 'ready_for_pickup',
  pickupCode: '1234',
  deliveryPin: '5678',
  vendorId: 'vendor-1',
  studentUserId: 'student-1',
  runnerUserId: 'runner-1',
};

const HANDOFF_PHOTO_URL = 'https://cdn.example.com/handoff/test.jpg';

describe('OrdersService.verifyPickup', () => {
  it('rejects a mismatched pickup code and never advances status', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });

    await expect(service.verifyPickup('order-1', '0000', HANDOFF_PHOTO_URL)).rejects.toThrow(BadRequestException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('advances to picked_up on a matching code, persisting the required handoff photo', async () => {
    const { service, prisma, redis } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });
    prisma.order.update.mockResolvedValue({ ...baseOrder, status: 'picked_up', handoffPhotoUrl: HANDOFF_PHOTO_URL });

    const result = await service.verifyPickup('order-1', '1234', HANDOFF_PHOTO_URL);

    expect(result).toEqual({ status: 'picked_up' });
    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'picked_up', handoffPhotoUrl: HANDOFF_PHOTO_URL, pickedUpAt: expect.any(Date) },
    });
    expect(redis.del).toHaveBeenCalled();
  });

  it('is idempotent — a retried correct scan after pickup already succeeded just confirms state', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    const result = await service.verifyPickup('order-1', '1234', HANDOFF_PHOTO_URL);

    expect(result).toEqual({ status: 'picked_up' });
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rejects when the order is not awaiting pickup at all (e.g. cancelled)', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'cancelled' });

    await expect(service.verifyPickup('order-1', '1234', HANDOFF_PHOTO_URL)).rejects.toThrow(ConflictException);
  });

  it('rejects pickup verification before the vendor marks the order ready (Task 12)', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'preparing' });

    await expect(service.verifyPickup('order-1', '1234', HANDOFF_PHOTO_URL)).rejects.toThrow(ConflictException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rate-limits after repeated failures on the same order', async () => {
    const { service, prisma, redis } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });

    let attempts = 0;
    redis.get.mockImplementation(async () => (attempts >= 5 ? String(attempts) : null));
    redis.incr.mockImplementation(async () => ++attempts);

    for (let i = 0; i < 5; i++) {
      await expect(service.verifyPickup('order-1', '0000', HANDOFF_PHOTO_URL)).rejects.toThrow(BadRequestException);
    }
    await expect(service.verifyPickup('order-1', '0000', HANDOFF_PHOTO_URL)).rejects.toThrow(HttpException);
    await expect(service.verifyPickup('order-1', '0000', HANDOFF_PHOTO_URL)).rejects.toMatchObject({ status: 429 });
  });
});

describe('OrdersService.verifyDelivery', () => {
  it('rejects a mismatched delivery PIN and never releases escrow', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    await expect(service.verifyDelivery('order-1', '0000')).rejects.toThrow(BadRequestException);
    expect(escrow.release).not.toHaveBeenCalled();
  });

  it('rejects verification before pickup has happened', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'placed' });

    await expect(service.verifyDelivery('order-1', '5678')).rejects.toThrow(ConflictException);
    expect(escrow.release).not.toHaveBeenCalled();
  });

  it('releases escrow exactly once on a matching PIN, and a retried correct submission never releases again', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    const first = await service.verifyDelivery('order-1', '5678');
    expect(first).toEqual({ status: 'delivered' });
    expect(escrow.release).toHaveBeenCalledTimes(1);

    // Simulate the order now reflecting the released state, as a real
    // retried request against the backend would see.
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'delivered' });
    const retried = await service.verifyDelivery('order-1', '5678');

    expect(retried).toEqual({ status: 'delivered' });
    expect(escrow.release).toHaveBeenCalledTimes(1);
  });

  it('rate-limits after repeated failures on the same order', async () => {
    const { service, prisma, redis } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    let attempts = 0;
    redis.get.mockImplementation(async () => (attempts >= 5 ? String(attempts) : null));
    redis.incr.mockImplementation(async () => ++attempts);

    for (let i = 0; i < 5; i++) {
      await expect(service.verifyDelivery('order-1', '0000')).rejects.toThrow(BadRequestException);
    }
    await expect(service.verifyDelivery('order-1', '0000')).rejects.toMatchObject({ status: 429 });
  });
});

describe('OrdersService.submitDeliveryProof', () => {
  it('flags the order for manual review without marking it delivered', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });
    prisma.order.update.mockResolvedValue({ ...baseOrder, status: 'picked_up', needsManualReview: true });

    const result = await service.submitDeliveryProof('order-1', { photoUrl: 'https://cdn.example.com/proof.jpg' });

    expect(result.status).toBe('picked_up');
    expect(prisma.order.update).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: expect.objectContaining({
        deliveryProofUrl: 'https://cdn.example.com/proof.jpg',
        needsManualReview: true,
      }),
    });
  });

  it('rejects proof submission before pickup', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'placed' });

    await expect(
      service.submitDeliveryProof('order-1', { photoUrl: 'https://cdn.example.com/proof.jpg' }),
    ).rejects.toThrow(ConflictException);
  });

  it('also opens an admin-facing dispute (Task 13c), upserting so a resubmitted proof never violates orderId uniqueness', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });
    prisma.order.update.mockResolvedValue({ ...baseOrder, status: 'picked_up', needsManualReview: true });

    await service.submitDeliveryProof('order-1', { photoUrl: 'https://cdn.example.com/proof.jpg' });

    expect(prisma.dispute.upsert).toHaveBeenCalledWith({
      where: { orderId: 'order-1' },
      create: { orderId: 'order-1', reason: 'Delivery proof submitted — PIN verification unavailable' },
      update: {},
    });
  });
});

describe('OrdersService.getOrderForViewer', () => {
  function orderWithVendor(overrides: Partial<typeof baseOrder> = {}) {
    return {
      ...baseOrder,
      ...overrides,
      vendor: { userId: 'vendor-owner-1', businessName: 'Tantalizers' },
      items: [],
    };
  }

  it('shows the pickup code to the owning vendor, not the delivery PIN', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(orderWithVendor());

    const result = await service.getOrderForViewer('order-1', { sub: 'vendor-owner-1', role: 'user' });

    expect(result.pickupCode).toBe('1234');
    expect(result.deliveryPin).toBeUndefined();
  });

  it('shows the delivery PIN to the student, not the pickup code', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(orderWithVendor());

    const result = await service.getOrderForViewer('order-1', { sub: 'student-1', role: 'user' });

    expect(result.deliveryPin).toBe('5678');
    expect(result.pickupCode).toBeUndefined();
  });

  it('shows neither code to the assigned runner', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(orderWithVendor());

    const result = await service.getOrderForViewer('order-1', { sub: 'runner-1', role: 'user' });

    expect(result.pickupCode).toBeUndefined();
    expect(result.deliveryPin).toBeUndefined();
  });

  // Task 46: the detail view's real timestamped lifecycle.
  it('includes vendor name, items, and the full timestamped lifecycle for any party', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(
      orderWithVendor({
        acceptedAt: new Date('2026-01-01T10:02:00.000Z'),
        pickedUpAt: new Date('2026-01-01T10:20:00.000Z'),
        deliveredAt: null,
        cancelledAt: null,
      } as Partial<typeof baseOrder>),
    );

    const result = await service.getOrderForViewer('order-1', { sub: 'student-1', role: 'user' });

    expect(result.vendorName).toBe('Tantalizers');
    expect(result.acceptedAt).toEqual(new Date('2026-01-01T10:02:00.000Z'));
    expect(result.pickedUpAt).toEqual(new Date('2026-01-01T10:20:00.000Z'));
    expect(result.deliveredAt).toBeNull();
  });

  it('rejects a caller who is not a party to the order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(orderWithVendor());

    await expect(
      service.getOrderForViewer('order-1', { sub: 'stranger-1', role: 'user' }),
    ).rejects.toThrow(ForbiddenException);
  });
});

// Task 46: real order history for students — replaces the old
// hardcoded-fake "Past" tab and the in-memory-only Cancelled tab.
describe('OrdersService.getOrderHistoryForStudent', () => {
  function historyOrder(overrides: Record<string, unknown> = {}) {
    return {
      id: 'order-1',
      status: 'delivered',
      totalAmount: 3500,
      note: null,
      deliveryLocationLabel: 'Hostel B',
      vendor: { businessName: 'Tantalizers' },
      items: [{ nameSnapshot: 'Jollof Rice', quantity: 2, priceSnapshot: 1500 }],
      createdAt: new Date('2026-01-01T10:00:00.000Z'),
      acceptedAt: new Date('2026-01-01T10:02:00.000Z'),
      pickedUpAt: new Date('2026-01-01T10:20:00.000Z'),
      deliveredAt: new Date('2026-01-01T10:35:00.000Z'),
      cancelledAt: null,
      ...overrides,
    };
  }

  it('scopes to exactly the calling student, most recent first', async () => {
    const { service, prisma } = makeService();
    prisma.order.findMany.mockResolvedValue([]);
    prisma.order.count.mockResolvedValue(0);

    await service.getOrderHistoryForStudent('student-1', 1, 20);

    expect(prisma.order.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { studentUserId: 'student-1' },
        orderBy: { createdAt: 'desc' },
      }),
    );
  });

  it('paginates with skip/take derived from page and limit', async () => {
    const { service, prisma } = makeService();
    prisma.order.findMany.mockResolvedValue([]);
    prisma.order.count.mockResolvedValue(47);

    const result = await service.getOrderHistoryForStudent('student-1', 3, 10);

    expect(prisma.order.findMany).toHaveBeenCalledWith(expect.objectContaining({ skip: 20, take: 10 }));
    expect(result).toEqual({ items: [], total: 47, page: 3, limit: 10 });
  });

  it('shapes each order with its vendor name, items, and full timestamped lifecycle', async () => {
    const { service, prisma } = makeService();
    prisma.order.findMany.mockResolvedValue([historyOrder()]);
    prisma.order.count.mockResolvedValue(1);

    const result = await service.getOrderHistoryForStudent('student-1', 1, 20);

    expect(result.items).toEqual([
      {
        id: 'order-1',
        status: 'delivered',
        vendorName: 'Tantalizers',
        totalAmount: 3500,
        note: null,
        deliveryLocationLabel: 'Hostel B',
        items: [{ name: 'Jollof Rice', quantity: 2, priceKobo: 1500 }],
        createdAt: new Date('2026-01-01T10:00:00.000Z'),
        acceptedAt: new Date('2026-01-01T10:02:00.000Z'),
        pickedUpAt: new Date('2026-01-01T10:20:00.000Z'),
        deliveredAt: new Date('2026-01-01T10:35:00.000Z'),
        cancelledAt: null,
      },
    ]);
  });

  it('includes cancelled orders in the same list, with cancelledAt set and no delivery timestamps', async () => {
    const { service, prisma } = makeService();
    prisma.order.findMany.mockResolvedValue([
      historyOrder({
        status: 'cancelled',
        pickedUpAt: null,
        deliveredAt: null,
        cancelledAt: new Date('2026-01-01T10:05:00.000Z'),
      }),
    ]);
    prisma.order.count.mockResolvedValue(1);

    const result = await service.getOrderHistoryForStudent('student-1', 1, 20);

    expect(result.items[0].status).toBe('cancelled');
    expect(result.items[0].cancelledAt).toEqual(new Date('2026-01-01T10:05:00.000Z'));
    expect(result.items[0].deliveredAt).toBeNull();
  });
});

// Task 30: the real student-facing "report a problem" entry point.
describe('OrdersService.reportProblem', () => {
  it('creates a real Dispute for the ordering student, with the reason and optional photo', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });
    prisma.dispute.findUnique.mockResolvedValue(null);
    prisma.dispute.create.mockResolvedValue({ id: 'dispute-1', orderId: 'order-1', status: 'open' });

    await service.reportProblem('order-1', 'student-1', {
      reason: 'My food arrived cold and half-eaten.',
      photoUrl: 'https://cdn.example.com/dispute-report/test.jpg',
    });

    expect(prisma.dispute.create).toHaveBeenCalledWith({
      data: {
        orderId: 'order-1',
        reason: 'My food arrived cold and half-eaten.',
        reporterPhotoUrl: 'https://cdn.example.com/dispute-report/test.jpg',
      },
    });
  });

  it('works with no photo at all — it is optional', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });
    prisma.dispute.findUnique.mockResolvedValue(null);
    prisma.dispute.create.mockResolvedValue({ id: 'dispute-1', orderId: 'order-1', status: 'open' });

    await service.reportProblem('order-1', 'student-1', { reason: 'Missing an item from my order.' });

    expect(prisma.dispute.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', reason: 'Missing an item from my order.', reporterPhotoUrl: undefined },
    });
  });

  it('rejects a caller who is not the ordering student — scoped to their own order only', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });

    await expect(
      service.reportProblem('order-1', 'a-different-student', { reason: 'Not my order' }),
    ).rejects.toThrow(ForbiddenException);
    expect(prisma.dispute.create).not.toHaveBeenCalled();
  });

  it('rejects a second report when a dispute already exists for this order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });
    prisma.dispute.findUnique.mockResolvedValue({ id: 'dispute-1', orderId: 'order-1' });

    await expect(
      service.reportProblem('order-1', 'student-1', { reason: 'Second report' }),
    ).rejects.toThrow(ConflictException);
    expect(prisma.dispute.create).not.toHaveBeenCalled();
  });

  it('throws when the order does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await expect(
      service.reportProblem('missing-order', 'student-1', { reason: 'x' }),
    ).rejects.toThrow(NotFoundException);
  });
});
