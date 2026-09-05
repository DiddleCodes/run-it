import { MatchingService } from '../src/matching/matching.service';
import { escalateJobId, rebroadcastJobId } from '../src/matching/matching.constants';
import { createConfigMock, createPrismaMock } from './support/mocks';

const MATCHING_CONFIG = {
  'matching.rebroadcastSeconds': 20,
  'matching.escalateSeconds': 120,
};

function makeService() {
  const prisma = createPrismaMock();
  const config = createConfigMock(MATCHING_CONFIG);
  const gateway = { broadcastNewJob: jest.fn() };
  const queue = { add: jest.fn().mockResolvedValue(undefined), remove: jest.fn().mockResolvedValue(undefined) };
  const service = new MatchingService(queue as any, gateway as any, prisma as any, config as any);
  return { service, prisma, config, gateway, queue };
}

describe('MatchingService.broadcastNewJob', () => {
  it('emits the broadcast (with the vendor\'s campusId) and schedules both a re-broadcast and an escalation job', async () => {
    const { service, prisma, gateway, queue } = makeService();
    prisma.order.findUnique.mockResolvedValue({
      id: 'order-1',
      vendorId: 'vendor-1',
      vendor: { user: { campusId: 'campus-1' } },
    });

    await service.broadcastNewJob('order-1');

    expect(gateway.broadcastNewJob).toHaveBeenCalledWith({ orderId: 'order-1', vendorId: 'vendor-1', campusId: 'campus-1' });
    expect(queue.add).toHaveBeenCalledWith(
      'rebroadcast',
      { orderId: 'order-1' },
      expect.objectContaining({ jobId: rebroadcastJobId('order-1'), delay: 20_000 }),
    );
    expect(queue.add).toHaveBeenCalledWith(
      'escalate',
      { orderId: 'order-1' },
      expect.objectContaining({ jobId: escalateJobId('order-1'), delay: 120_000 }),
    );
  });

  it('does nothing for an unknown order', async () => {
    const { service, prisma, gateway, queue } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await service.broadcastNewJob('missing-order');

    expect(gateway.broadcastNewJob).not.toHaveBeenCalled();
    expect(queue.add).not.toHaveBeenCalled();
  });
});

describe('MatchingService.handleRebroadcast', () => {
  it('re-emits the broadcast when still unclaimed and still waiting', async () => {
    const { service, prisma, gateway } = makeService();
    prisma.order.findUnique.mockResolvedValue({
      id: 'order-1',
      vendorId: 'vendor-1',
      runnerUserId: null,
      status: 'preparing',
      vendor: { user: { campusId: 'campus-1' } },
    });

    await service.handleRebroadcast('order-1');

    expect(gateway.broadcastNewJob).toHaveBeenCalledWith({ orderId: 'order-1', vendorId: 'vendor-1', campusId: 'campus-1' });
  });

  it('does not re-emit once a runner has claimed it', async () => {
    const { service, prisma, gateway } = makeService();
    prisma.order.findUnique.mockResolvedValue({
      id: 'order-1',
      vendorId: 'vendor-1',
      runnerUserId: 'runner-1',
      status: 'preparing',
      vendor: { user: { campusId: 'campus-1' } },
    });

    await service.handleRebroadcast('order-1');

    expect(gateway.broadcastNewJob).not.toHaveBeenCalled();
  });

  it('does not re-emit once the order has moved past a claimable status (e.g. cancelled)', async () => {
    const { service, prisma, gateway } = makeService();
    prisma.order.findUnique.mockResolvedValue({
      id: 'order-1',
      vendorId: 'vendor-1',
      runnerUserId: null,
      status: 'cancelled',
      vendor: { user: { campusId: 'campus-1' } },
    });

    await service.handleRebroadcast('order-1');

    expect(gateway.broadcastNewJob).not.toHaveBeenCalled();
  });
});

describe('MatchingService.handleEscalate', () => {
  it('creates a Dispute when still unclaimed past the matching window', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-1', runnerUserId: null, status: 'preparing' });
    prisma.dispute.upsert.mockResolvedValue({ id: 'dispute-1' });

    await service.handleEscalate('order-1');

    expect(prisma.dispute.upsert).toHaveBeenCalledWith({
      where: { orderId: 'order-1' },
      create: { orderId: 'order-1', reason: 'No runner claimed this order within the matching window' },
      update: {},
    });
  });

  it('does not escalate once a runner has claimed it', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1', vendorId: 'vendor-1', runnerUserId: 'runner-1', status: 'preparing' });

    await service.handleEscalate('order-1');

    expect(prisma.dispute.upsert).not.toHaveBeenCalled();
  });
});

describe('MatchingService.listAvailable', () => {
  it('rejects a non-runner account', async () => {
    const { service } = makeService();
    await expect(
      service.listAvailable({ sub: 'student-1', accountType: 'student', role: 'user' } as any),
    ).rejects.toThrow('Only runner accounts can browse available orders');
  });

  it('maps still-waiting, unclaimed orders into available jobs, skipping any without an escrow', async () => {
    const { service, prisma } = makeService();
    const createdAt = new Date('2026-08-31T12:00:00.000Z');
    prisma.order.findMany.mockResolvedValue([
      {
        id: 'order-1',
        vendorId: 'vendor-1',
        vendor: { businessName: 'Tantalizers' },
        deliveryLocationLabel: 'Queen Elizabeth II Hall',
        totalAmount: 10_000,
        escrow: { runnerShare: 850 },
        createdAt,
      },
      {
        id: 'order-2',
        vendorId: 'vendor-2',
        vendor: { businessName: 'No Escrow Yet' },
        deliveryLocationLabel: null,
        totalAmount: 5_000,
        escrow: null,
        createdAt,
      },
    ]);

    const jobs = await service.listAvailable({ sub: 'runner-1', accountType: 'runner', role: 'user', campusId: 'campus-1' } as any);

    expect(prisma.order.findMany).toHaveBeenCalledWith({
      where: {
        runnerUserId: null,
        status: { in: ['preparing', 'ready_for_pickup'] },
        vendor: { user: { campusId: 'campus-1' } },
      },
      include: { vendor: true, escrow: true },
      orderBy: { createdAt: 'asc' },
    });
    expect(jobs).toEqual([
      {
        orderId: 'order-1',
        vendorId: 'vendor-1',
        vendorName: 'Tantalizers',
        deliveryLocationLabel: 'Queen Elizabeth II Hall',
        payoutAmount: 850,
        totalAmount: 10_000,
        isPayOnDelivery: false,
        createdAt,
      },
    ]);
  });

  it('flags a Pay on Delivery order as isPayOnDelivery for the runner job card', async () => {
    const { service, prisma } = makeService();
    const createdAt = new Date('2026-08-31T12:00:00Z');
    prisma.order.findMany.mockResolvedValue([
      {
        id: 'order-1',
        vendorId: 'vendor-1',
        vendor: { businessName: 'Tantalizers' },
        deliveryLocationLabel: 'Queen Elizabeth II Hall',
        totalAmount: 10_000,
        paymentMethod: 'pay_on_delivery',
        escrow: { runnerShare: 850 },
        createdAt,
      },
    ]);

    const jobs = await service.listAvailable({ sub: 'runner-1', accountType: 'runner', role: 'user', campusId: 'campus-1' } as any);

    expect(jobs[0].isPayOnDelivery).toBe(true);
  });

  // Task 26.
  it('returns an empty list without querying the database for a runner with no assigned campus', async () => {
    const { service, prisma } = makeService();

    const jobs = await service.listAvailable({ sub: 'runner-1', accountType: 'runner', role: 'user', campusId: null } as any);

    expect(prisma.order.findMany).not.toHaveBeenCalled();
    expect(jobs).toEqual([]);
  });
});

describe('MatchingService.cancelPendingJobs', () => {
  it('removes both the pending re-broadcast and escalation jobs by their deterministic ids', async () => {
    const { service, queue } = makeService();

    await service.cancelPendingJobs('order-1');

    expect(queue.remove).toHaveBeenCalledWith(rebroadcastJobId('order-1'));
    expect(queue.remove).toHaveBeenCalledWith(escalateJobId('order-1'));
  });

  it('never throws even if a job id no longer exists', async () => {
    const { service, queue } = makeService();
    queue.remove.mockRejectedValue(new Error('job not found'));

    await expect(service.cancelPendingJobs('order-1')).resolves.toBeUndefined();
  });
});
