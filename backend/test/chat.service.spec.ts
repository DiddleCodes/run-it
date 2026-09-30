import { ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { ChatService } from '../src/chat/chat.service';

const ORDER = 'order-1';
const STUDENT = 'student-1';
const RUNNER = 'runner-1';

function makeService(order: Record<string, unknown> | null = { id: ORDER, status: 'picked_up', studentUserId: STUDENT, runnerUserId: RUNNER }) {
  const prisma = {
    order: {
      findUnique: jest.fn().mockResolvedValue(order),
      findUniqueOrThrow: jest.fn().mockResolvedValue({
        vendor: { businessName: 'Golden Crust Bakery' },
        studentUser: { name: 'Ayanfe Ogunleye' },
        runnerUser: { name: 'Amaka Nwosu' },
      }),
      findMany: jest.fn().mockResolvedValue([]),
    },
    message: {
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(async ({ data }: { data: Record<string, string> }) => ({ id: 'm1', createdAt: new Date(), readAt: null, ...data })),
      updateMany: jest.fn().mockResolvedValue({ count: 2 }),
      groupBy: jest.fn().mockResolvedValue([]),
    },
    user: { findUnique: jest.fn().mockResolvedValue({ name: 'Amaka Nwosu' }) },
  };
  const gateway = {
    broadcastMessage: jest.fn(),
    broadcastRead: jest.fn(),
    isUserConnected: jest.fn().mockResolvedValue(false),
  };
  const notifications = { emit: jest.fn() };
  const service = new ChatService(prisma as any, gateway as any, notifications as any);
  return { service, prisma, gateway, notifications };
}

describe('ChatService — who may use an order’s chat', () => {
  it('lets the student read the history, with the runner as the other party', async () => {
    const { service } = makeService();
    const history = await service.history(ORDER, STUDENT);
    expect(history).toMatchObject({ canSend: true, myRole: 'student', otherPartyName: 'Amaka N.', vendorName: 'Golden Crust Bakery' });
  });

  it('lets the runner read it, with the student as the other party', async () => {
    const { service } = makeService();
    await expect(service.history(ORDER, RUNNER)).resolves.toMatchObject({ myRole: 'runner', otherPartyName: 'Ayanfe O.' });
  });

  it('refuses a third party — even another signed-in student', async () => {
    const { service, prisma } = makeService();
    await expect(service.history(ORDER, 'student-2')).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.send(ORDER, 'student-2', 'hi')).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.markRead(ORDER, 'student-2')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.message.create).not.toHaveBeenCalled();
  });

  it('has no chat before a runner is assigned', async () => {
    const { service } = makeService({ id: ORDER, status: 'preparing', studentUserId: STUDENT, runnerUserId: null });
    await expect(service.history(ORDER, STUDENT)).rejects.toThrow('Chat opens once a runner is assigned.');
  });

  it('404s an order that does not exist', async () => {
    const { service } = makeService(null);
    await expect(service.history(ORDER, STUDENT)).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('ChatService.send', () => {
  it('stores the message, then broadcasts it to both participants', async () => {
    const { service, prisma, gateway } = makeService();
    const message = await service.send(ORDER, STUDENT, '  I’m at the side gate  ');

    expect(prisma.message.create).toHaveBeenCalledWith({ data: { orderId: ORDER, senderUserId: STUDENT, body: 'I’m at the side gate' } });
    expect(gateway.broadcastMessage).toHaveBeenCalledWith(message, [STUDENT, RUNNER]);
  });

  it('pushes a "new message" to the recipient when their app is closed or backgrounded', async () => {
    const { service, gateway, notifications } = makeService();
    gateway.isUserConnected.mockResolvedValue(false);

    await service.send(ORDER, RUNNER, 'Outside Queen Elizabeth II Hall');

    expect(gateway.isUserConnected).toHaveBeenCalledWith(STUDENT);
    expect(notifications.emit).toHaveBeenCalledWith({
      type: 'chat_message',
      recipientUserId: STUDENT,
      title: 'Amaka N. (your runner)',
      body: 'Outside Queen Elizabeth II Hall',
      data: { orderId: ORDER },
      persist: false,
    });
  });

  it('does not push when the recipient has the app open — the live socket already reached them', async () => {
    const { service, gateway, notifications } = makeService();
    gateway.isUserConnected.mockResolvedValue(true);

    await service.send(ORDER, RUNNER, 'On my way');

    expect(notifications.emit).not.toHaveBeenCalled();
  });

  it('shortens a long message in the push preview', async () => {
    const { service, notifications } = makeService();
    await service.send(ORDER, STUDENT, 'x'.repeat(300));
    expect(notifications.emit.mock.calls[0][0].body).toHaveLength(140);
  });

  it.each(['delivered', 'cancelled'])('refuses to send once the order is %s (history stays readable)', async (status) => {
    const { service, prisma } = makeService({ id: ORDER, status, studentUserId: STUDENT, runnerUserId: RUNNER });
    await expect(service.send(ORDER, STUDENT, 'Thanks!')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.message.create).not.toHaveBeenCalled();
    await expect(service.history(ORDER, STUDENT)).resolves.toMatchObject({ canSend: false });
  });

  it('refuses an empty message', async () => {
    const { service, prisma } = makeService();
    await expect(service.send(ORDER, STUDENT, '   ')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.message.create).not.toHaveBeenCalled();
  });
});

describe('ChatService.markRead', () => {
  it("marks only the other party's unread messages, and tells the room", async () => {
    const { service, prisma, gateway } = makeService();

    await expect(service.markRead(ORDER, STUDENT)).resolves.toEqual({ updated: 2 });

    expect(prisma.message.updateMany).toHaveBeenCalledWith({
      where: { orderId: ORDER, senderUserId: { not: STUDENT }, readAt: null },
      data: { readAt: expect.any(Date) },
    });
    expect(gateway.broadcastRead).toHaveBeenCalledWith(ORDER, STUDENT, expect.any(Date));
  });
});

describe('ChatService.threads', () => {
  it("builds the runner's threads from their real orders, newest activity first, with unread counts", async () => {
    const { service, prisma } = makeService();
    const old = new Date('2026-09-29T10:00:00Z');
    const recent = new Date('2026-09-30T10:00:00Z');
    prisma.order.findMany.mockResolvedValue([
      { id: 'o-old', status: 'delivered', studentUserId: 's1', runnerUserId: RUNNER, updatedAt: old, vendor: { businessName: 'Tantalizers' }, studentUser: { name: 'Tolu Bello' }, runnerUser: { name: 'Amaka Nwosu' } },
      { id: 'o-new', status: 'picked_up', studentUserId: 's2', runnerUserId: RUNNER, updatedAt: old, vendor: { businessName: 'Golden Crust Bakery' }, studentUser: { name: 'Ayanfe Ogunleye' }, runnerUser: { name: 'Amaka Nwosu' } },
    ]);
    prisma.message.findMany.mockResolvedValue([{ id: 'm9', orderId: 'o-new', senderUserId: 's2', body: 'Which gate?', createdAt: recent, readAt: null }]);
    prisma.message.groupBy.mockResolvedValue([{ orderId: 'o-new', _count: { _all: 1 } }]);

    const threads = await service.threads(RUNNER);

    expect(prisma.order.findMany.mock.calls[0][0].where).toEqual({
      runnerUserId: { not: null },
      OR: [{ studentUserId: RUNNER }, { runnerUserId: RUNNER }],
    });
    expect(threads.map((t) => t.orderId)).toEqual(['o-new', 'o-old']);
    expect(threads[0]).toMatchObject({ canSend: true, myRole: 'runner', otherPartyName: 'Ayanfe O.', unreadCount: 1, lastMessage: { body: 'Which gate?' } });
    expect(threads[1]).toMatchObject({ canSend: false, lastMessage: null, unreadCount: 0 });
  });
});
