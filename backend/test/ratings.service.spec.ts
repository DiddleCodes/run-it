import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { RatingsService } from '../src/ratings/ratings.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const service = new RatingsService(prisma as any);
  return { service, prisma };
}

const DELIVERED_ORDER = {
  id: 'order-1',
  studentUserId: 'student-1',
  runnerUserId: 'runner-1',
  vendorId: 'vendor-1',
  status: 'delivered',
};

describe('RatingsService.rate', () => {
  it("rejects rating an order that is not the caller's own", async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);

    await expect(
      service.rate('order-1', 'someone-else', { runner: { stars: 5 } }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('rejects rating an order that has not been delivered yet', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...DELIVERED_ORDER, status: 'placed' });

    await expect(service.rate('order-1', 'student-1', { runner: { stars: 5 } })).rejects.toThrow(ConflictException);
  });

  it('rejects when neither a runner nor a vendor rating is provided', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);

    await expect(service.rate('order-1', 'student-1', {})).rejects.toThrow(BadRequestException);
    expect(prisma.order.findUnique).not.toHaveBeenCalled();
  });

  it('rejects a duplicate runner rating for the same order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.runnerRating.findUnique.mockResolvedValue({ id: 'existing-rating' });

    await expect(service.rate('order-1', 'student-1', { runner: { stars: 5 } })).rejects.toThrow(ConflictException);
    expect(prisma.runnerRating.create).not.toHaveBeenCalled();
  });

  it('rejects a duplicate vendor rating for the same order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.vendorRating.findUnique.mockResolvedValue({ id: 'existing-rating' });

    await expect(service.rate('order-1', 'student-1', { vendor: { stars: 5 } })).rejects.toThrow(ConflictException);
    expect(prisma.vendorRating.create).not.toHaveBeenCalled();
  });

  it('throws if the order does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await expect(service.rate('order-x', 'student-1', { runner: { stars: 5 } })).rejects.toThrow(NotFoundException);
  });

  it("creates the runner rating and recalculates the runner's cached average/count", async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.runnerRating.findUnique.mockResolvedValue(null);
    prisma.runnerRating.create.mockResolvedValue({
      id: 'rating-1',
      orderId: 'order-1',
      runnerId: 'runner-1',
      studentId: 'student-1',
      stars: 4,
    });
    prisma.runnerRating.aggregate.mockResolvedValue({ _avg: { stars: 4.5 }, _count: { stars: 2 } });

    const result = await service.rate('order-1', 'student-1', { runner: { stars: 4, comment: 'Fast delivery' } });

    expect(result.runner?.id).toBe('rating-1');
    expect(result.vendor).toBeUndefined();
    expect(prisma.runnerRating.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', runnerId: 'runner-1', studentId: 'student-1', stars: 4, comment: 'Fast delivery' },
    });
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'runner-1' },
      data: { averageRating: 4.5, ratingCount: 2 },
    });
    expect(prisma.vendorRating.create).not.toHaveBeenCalled();
  });

  it("creates the vendor rating and recalculates the restaurant's cached average/count", async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.vendorRating.findUnique.mockResolvedValue(null);
    prisma.vendorRating.create.mockResolvedValue({
      id: 'vrating-1',
      orderId: 'order-1',
      vendorId: 'vendor-1',
      studentId: 'student-1',
      stars: 3,
    });
    prisma.vendorRating.aggregate.mockResolvedValue({ _avg: { stars: 3.5 }, _count: { stars: 6 } });

    const result = await service.rate('order-1', 'student-1', { vendor: { stars: 3 } });

    expect(result.vendor?.id).toBe('vrating-1');
    expect(result.runner).toBeUndefined();
    expect(prisma.vendorRating.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', vendorId: 'vendor-1', studentId: 'student-1', stars: 3, comment: undefined },
    });
    expect(prisma.vendor.update).toHaveBeenCalledWith({
      where: { id: 'vendor-1' },
      data: { averageRating: 3.5, ratingCount: 6 },
    });
  });

  it('rates the runner and the restaurant together in one request', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.runnerRating.findUnique.mockResolvedValue(null);
    prisma.vendorRating.findUnique.mockResolvedValue(null);
    prisma.runnerRating.create.mockResolvedValue({ id: 'rating-1' });
    prisma.vendorRating.create.mockResolvedValue({ id: 'vrating-1' });
    prisma.runnerRating.aggregate.mockResolvedValue({ _avg: { stars: 5 }, _count: { stars: 1 } });
    prisma.vendorRating.aggregate.mockResolvedValue({ _avg: { stars: 4 }, _count: { stars: 1 } });

    const result = await service.rate('order-1', 'student-1', {
      runner: { stars: 5 },
      vendor: { stars: 4 },
    });

    expect(result.runner?.id).toBe('rating-1');
    expect(result.vendor?.id).toBe('vrating-1');
  });

  it('rejects rating the runner on an order with no assigned runner', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...DELIVERED_ORDER, runnerUserId: null });

    await expect(service.rate('order-1', 'student-1', { runner: { stars: 5 } })).rejects.toThrow(ConflictException);
  });
});

describe('RatingsService.summary', () => {
  it('returns zeroed stats for a runner with no ratings yet', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', averageRating: null, ratingCount: 0 });

    const result = await service.summary('runner-1');

    expect(result).toEqual({ runnerId: 'runner-1', averageRating: 0, ratingCount: 0 });
  });

  it('throws if the runner does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.summary('nope')).rejects.toThrow(NotFoundException);
  });
});

describe('RatingsService.vendorSummary', () => {
  it('returns zeroed stats for a restaurant with no ratings yet', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', averageRating: null, ratingCount: 0 });

    const result = await service.vendorSummary('vendor-1');

    expect(result).toEqual({ vendorId: 'vendor-1', averageRating: 0, ratingCount: 0 });
  });

  it('throws if the vendor does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue(null);

    await expect(service.vendorSummary('nope')).rejects.toThrow(NotFoundException);
  });
});
