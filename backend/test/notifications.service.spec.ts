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

  it('Task 78: a push-only event (persist: false) is pushed but never stored', async () => {
    const { service, prisma, fcmQueue } = makeService();

    await service.handle({ ...baseEvent, type: 'chat_message', persist: false });

    expect(prisma.notification.create).not.toHaveBeenCalled();
    expect(fcmQueue.add).toHaveBeenCalledTimes(1);
  });

  it('enqueues an FCM push job for the recipient', async () => {
    const { service, fcmQueue } = makeService();

    await service.handle(baseEvent);

    expect(fcmQueue.add).toHaveBeenCalledWith(
      'push',
      { userId: 'user-1', payload: { title: baseEvent.title, body: baseEvent.body, data: { ...baseEvent.data, type: baseEvent.type } } },
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

describe('NotificationsService — unread state', () => {
  it('lists newest first with the unread count alongside the page', async () => {
    const { service, prisma } = makeService();
    prisma.notification.findMany.mockResolvedValue([{ id: 'n2' }, { id: 'n1' }]);
    prisma.notification.count.mockImplementation(({ where }: any) => Promise.resolve(where.readAt === null ? 1 : 2));

    const result = await service.list('user-1', {});

    expect(prisma.notification.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { userId: 'user-1' }, orderBy: { createdAt: 'desc' } }),
    );
    expect(result).toEqual({ items: [{ id: 'n2' }, { id: 'n1' }], total: 2, unreadCount: 1, page: 1, limit: 20 });
  });

  it('marks one of my notifications read, once', async () => {
    const { service, prisma } = makeService();
    prisma.notification.findUnique.mockResolvedValue({ id: 'n1', userId: 'user-1', readAt: null });
    prisma.notification.update.mockResolvedValue({ id: 'n1', readAt: new Date() });

    await service.markRead('user-1', 'n1');
    expect(prisma.notification.update).toHaveBeenCalledWith({ where: { id: 'n1' }, data: { readAt: expect.any(Date) } });

    prisma.notification.update.mockClear();
    prisma.notification.findUnique.mockResolvedValue({ id: 'n1', userId: 'user-1', readAt: new Date() });
    await service.markRead('user-1', 'n1');
    expect(prisma.notification.update).not.toHaveBeenCalled();
  });

  it('marks all of my unread notifications read — and only mine', async () => {
    const { service, prisma } = makeService();
    prisma.notification.updateMany.mockResolvedValue({ count: 3 });

    await expect(service.markAllRead('user-1')).resolves.toEqual({ updated: 3 });
    expect(prisma.notification.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', readAt: null },
      data: { readAt: expect.any(Date) },
    });
  });
});

describe('NotificationsService — notifications for an order\'s restaurant', () => {
  it('finds the user who runs the order\'s restaurant, then stores and pushes as usual', async () => {
    const { service, prisma, fcmQueue } = makeService();
    prisma.order.findUnique.mockResolvedValue({ pickupCode: '5319', vendor: { userId: 'rest-user-1' } });

    await service.handleForOrderRestaurant({
      type: 'dispute_opened',
      orderId: 'order-1',
      title: 'Dispute opened',
      body: 'A dispute was opened on order {pickupCode}: Cold food',
    });

    // Named by the pickup code the restaurant's orders page shows.
    expect(prisma.notification.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        userId: 'rest-user-1',
        type: 'dispute_opened',
        body: 'A dispute was opened on order 5319: Cold food',
        data: { orderId: 'order-1', pickupCode: '5319' },
      }),
    });
    expect(fcmQueue.add).toHaveBeenCalledWith('push', expect.objectContaining({ userId: 'rest-user-1' }), expect.anything());
  });

  it('a new order still reaches the live restaurant-dashboard channel, named by pickup code', async () => {
    const { service, prisma, gateway } = makeService();
    prisma.order.findUnique.mockResolvedValue({ pickupCode: '5319', vendor: { userId: 'rest-user-1' } });

    await service.handleForOrderRestaurant({
      type: 'order_placed',
      orderId: 'order-1',
      title: 'New order received',
      body: 'Order {pickupCode} is waiting for you to accept it.',
      data: { vendorId: 'vendor-1' },
    });

    expect(gateway.notifyNewOrder).toHaveBeenCalledWith('vendor-1', {
      orderId: 'order-1',
      title: 'New order received',
      body: 'Order 5319 is waiting for you to accept it.',
      data: { vendorId: 'vendor-1', orderId: 'order-1', pickupCode: '5319' },
    });
  });

  it('does nothing for an order that no longer exists', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await service.handleForOrderRestaurant({ type: 'dispute_opened', orderId: 'gone', title: 't', body: 'b' });

    expect(prisma.notification.create).not.toHaveBeenCalled();
  });
});
