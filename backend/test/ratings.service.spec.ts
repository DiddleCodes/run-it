import { ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
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
  status: 'delivered',
};

describe('RatingsService.rate', () => {
  it('rejects rating an order that is not the caller\'s own', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);

    await expect(
      service.rate('order-1', 'someone-else', { stars: 5 }),
    ).rejects.toThrow(ForbiddenException);
  });

  it('rejects rating an order that has not been delivered yet', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ ...DELIVERED_ORDER, status: 'placed' });

    await expect(service.rate('order-1', 'student-1', { stars: 5 })).rejects.toThrow(ConflictException);
  });

  it('rejects a duplicate rating for the same order', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(DELIVERED_ORDER);
    prisma.runnerRating.findUnique.mockResolvedValue({ id: 'existing-rating' });

    await expect(service.rate('order-1', 'student-1', { stars: 5 })).rejects.toThrow(ConflictException);
    expect(prisma.runnerRating.create).not.toHaveBeenCalled();
  });

  it('throws if the order does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await expect(service.rate('order-x', 'student-1', { stars: 5 })).rejects.toThrow(NotFoundException);
  });

  it('creates the rating and recalculates the runner\'s cached average/count', async () => {
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

    const result = await service.rate('order-1', 'student-1', { stars: 4, comment: 'Fast delivery' });

    expect(result.id).toBe('rating-1');
    expect(prisma.runnerRating.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', runnerId: 'runner-1', studentId: 'student-1', stars: 4, comment: 'Fast delivery' },
    });
    expect(prisma.user.update).toHaveBeenCalledWith({
      where: { id: 'runner-1' },
      data: { averageRating: 4.5, ratingCount: 2 },
    });
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
