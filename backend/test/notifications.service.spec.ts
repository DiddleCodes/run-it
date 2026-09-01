import { NotificationsService } from '../src/notifications/notifications.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const fcmQueue = { add: jest.fn() };
  const gateway = { notifyNewOrder: jest.fn() };
  const service = new NotificationsService(prisma as any, fcmQueue as any, gateway as any);
  return { service, prisma, fcmQueue, gateway };
}

const baseEvent = {
  type: 'order_picked_up' as const,
  recipientUserId: 'user-1',
  title: 'Order picked up',
  body: 'Your order is on its way.',
  data: { orderId: 'order-1' },
};

describe('NotificationsService.handle', () => {
  it('persists a Notification row for every event', async () => {
    const { service, prisma } = makeService();

    await service.handle(baseEvent);

    expect(prisma.notification.create).toHaveBeenCalledWith({
      data: {
        userId: 'user-1',
        type: 'order_picked_up',
        title: 'Order picked up',
        body: 'Your order is on its way.',
        data: { orderId: 'order-1' },
      },
    });
  });

  it('enqueues an FCM push job for the recipient', async () => {
    const { service, fcmQueue } = makeService();

    await service.handle(baseEvent);

    expect(fcmQueue.add).toHaveBeenCalledWith(
      'push',
      { userId: 'user-1', payload: { title: baseEvent.title, body: baseEvent.body, data: baseEvent.data } },
      expect.objectContaining({ attempts: 3 }),
    );
  });

  it('routes order_placed events with a vendorId to the live restaurant-dashboard channel', async () => {
    const { service, gateway } = makeService();

    await service.handle({ ...baseEvent, type: 'order_placed', data: { orderId: 'order-1', vendorId: 'vendor-1' } });

    expect(gateway.notifyNewOrder).toHaveBeenCalledWith('vendor-1', {
      orderId: 'order-1',
      title: baseEvent.title,
      body: baseEvent.body,
      data: { orderId: 'order-1', vendorId: 'vendor-1' },
    });
  });

  it('never routes non-order_placed events to the live channel', async () => {
    const { service, gateway } = makeService();

    await service.handle(baseEvent);

    expect(gateway.notifyNewOrder).not.toHaveBeenCalled();
  });

  it('swallows a persistence failure rather than throwing into the caller', async () => {
    const { service, prisma } = makeService();
    prisma.notification.create.mockRejectedValue(new Error('db unreachable'));

    await expect(service.handle(baseEvent)).resolves.toBeUndefined();
  });
});

describe('NotificationsService.markRead', () => {
  it('rejects marking a notification that belongs to a different user', async () => {
    const { service, prisma } = makeService();
    prisma.notification.findUnique.mockResolvedValue({ id: 'n1', userId: 'someone-else', readAt: null });

    await expect(service.markRead('user-1', 'n1')).rejects.toThrow('Notification not found');
    expect(prisma.notification.update).not.toHaveBeenCalled();
  });
});
