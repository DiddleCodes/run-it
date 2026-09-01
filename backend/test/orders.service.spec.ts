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

describe('OrdersService.verifyPickup', () => {
  it('rejects a mismatched pickup code and never advances status', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });

    await expect(service.verifyPickup('order-1', '0000')).rejects.toThrow(BadRequestException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('advances to picked_up on a matching code', async () => {
    const { service, prisma, redis } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });
    prisma.order.update.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    const result = await service.verifyPickup('order-1', '1234');

    expect(result).toEqual({ status: 'picked_up' });
    expect(prisma.order.update).toHaveBeenCalledWith({ where: { id: 'order-1' }, data: { status: 'picked_up' } });
    expect(redis.del).toHaveBeenCalled();
  });

  it('is idempotent — a retried correct scan after pickup already succeeded just confirms state', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'picked_up' });

    const result = await service.verifyPickup('order-1', '1234');

    expect(result).toEqual({ status: 'picked_up' });
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rejects when the order is not awaiting pickup at all (e.g. cancelled)', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'cancelled' });

    await expect(service.verifyPickup('order-1', '1234')).rejects.toThrow(ConflictException);
  });

  it('rejects pickup verification before the vendor marks the order ready (Task 12)', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder, status: 'preparing' });

    await expect(service.verifyPickup('order-1', '1234')).rejects.toThrow(ConflictException);
    expect(prisma.order.update).not.toHaveBeenCalled();
  });

  it('rate-limits after repeated failures on the same order', async () => {
    const { service, prisma, redis } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...baseOrder });

    let attempts = 0;
    redis.get.mockImplementation(async () => (attempts >= 5 ? String(attempts) : null));
    redis.incr.mockImplementation(async () => ++attempts);

    for (let i = 0; i < 5; i++) {
      await expect(service.verifyPickup('order-1', '0000')).rejects.toThrow(BadRequestException);
    }
    await expect(service.verifyPickup('order-1', '0000')).rejects.toThrow(HttpException);
    await expect(service.verifyPickup('order-1', '0000')).rejects.toMatchObject({ status: 429 });
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
    return { ...baseOrder, ...overrides, vendor: { userId: 'vendor-owner-1' } };
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

  it('rejects a caller who is not a party to the order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(orderWithVendor());

    await expect(
      service.getOrderForViewer('order-1', { sub: 'stranger-1', role: 'user' }),
    ).rejects.toThrow(ForbiddenException);
  });
});
