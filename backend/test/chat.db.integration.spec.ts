/**
 * Task 78: ChatService against real Postgres — proves what a mocked Prisma
 * can't: the latest-message-per-order (`distinct`) and unread-count
 * (`groupBy`) queries behind the thread list, read receipts, and that a
 * finished order's chat really stops accepting messages.
 *
 * Skipped by default: `npm test` must not require a live database.
 *
 *   RUN_DB_INTEGRATION_TESTS=1 npx jest chat.db.integration
 */
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'crypto';
import { ChatService } from '../src/chat/chat.service';
import { generateVerificationCode } from '../src/orders/pin-code.util';

const RUN = process.env.RUN_DB_INTEGRATION_TESTS === '1';
const describeIfDb = RUN ? describe : describe.skip;

describeIfDb('ChatService — real database', () => {
  const prisma = new PrismaClient();
  const gateway = { broadcastMessage: jest.fn(), broadcastRead: jest.fn(), isUserConnected: jest.fn().mockResolvedValue(false) };
  const notifications = { emit: jest.fn() };
  const service = new ChatService(prisma as any, gateway as any, notifications as any);

  const studentId = randomUUID();
  const runnerId = randomUUID();
  const strangerId = randomUUID();
  const vendorUserId = randomUUID();
  const activeOrderId = randomUUID();
  const deliveredOrderId = randomUUID();
  let vendorId: string;

  beforeAll(async () => {
    await prisma.user.createMany({
      data: [
        { id: studentId, email: `t78-student-${studentId}@test.internal`, accountType: 'student', name: 'Ayanfe Ogunleye' },
        { id: runnerId, phone: `+234701${runnerId.slice(0, 7)}`, accountType: 'runner', name: 'Amaka Nwosu' },
        { id: strangerId, email: `t78-stranger-${strangerId}@test.internal`, accountType: 'student' },
        { id: vendorUserId, email: `t78-vendor-${vendorUserId}@test.internal`, accountType: 'restaurant' },
      ],
    });
    vendorId = (await prisma.vendor.create({ data: { userId: vendorUserId, businessName: 'T78 throwaway vendor', category: 'Test' } })).id;
    for (const [id, status] of [
      [deliveredOrderId, 'delivered'],
      [activeOrderId, 'picked_up'],
    ] as const) {
      await prisma.order.create({
        data: {
          id,
          studentUserId: studentId,
          runnerUserId: runnerId,
          vendorId,
          status,
          totalAmount: 10_000,
          pickupCode: generateVerificationCode(),
          deliveryPin: generateVerificationCode(),
        },
      });
    }
  });

  afterAll(async () => {
    const orderIds = [activeOrderId, deliveredOrderId];
    await prisma.message.deleteMany({ where: { orderId: { in: orderIds } } });
    await prisma.order.deleteMany({ where: { id: { in: orderIds } } });
    await prisma.vendor.delete({ where: { id: vendorId } });
    await prisma.user.deleteMany({ where: { id: { in: [studentId, runnerId, strangerId, vendorUserId] } } });
    await prisma.$disconnect();
  });

  it('round-trips a conversation, with unread counts and read receipts', async () => {
    await service.send(activeOrderId, studentId, 'Which way are you coming?');
    await service.send(activeOrderId, runnerId, 'From the library side');
    await service.send(activeOrderId, runnerId, 'Two minutes');

    const history = await service.history(activeOrderId, studentId);
    expect(history.messages.map((m) => m.body)).toEqual(['Which way are you coming?', 'From the library side', 'Two minutes']);

    let [thread] = (await service.threads(studentId)).filter((t) => t.orderId === activeOrderId);
    expect(thread).toMatchObject({ unreadCount: 2, otherPartyName: 'Amaka N.', lastMessage: { body: 'Two minutes' }, canSend: true });

    await expect(service.markRead(activeOrderId, studentId)).resolves.toEqual({ updated: 2 });
    [thread] = (await service.threads(studentId)).filter((t) => t.orderId === activeOrderId);
    expect(thread.unreadCount).toBe(0);

    // The runner's own unread is the student's one message, untouched above.
    const [runnerThread] = (await service.threads(runnerId)).filter((t) => t.orderId === activeOrderId);
    expect(runnerThread).toMatchObject({ unreadCount: 1, otherPartyName: 'Ayanfe O.' });
  });

  it("lists the runner's past orders too (read-only), newest activity first", async () => {
    const threads = await service.threads(runnerId);
    expect(threads.map((t) => t.orderId)).toEqual([activeOrderId, deliveredOrderId]);
    expect(threads[1]).toMatchObject({ canSend: false, lastMessage: null });
  });

  it('keeps a delivered order readable but closed to new messages', async () => {
    await expect(service.send(deliveredOrderId, studentId, 'Thanks!')).rejects.toThrow('chat is closed');
    await expect(service.history(deliveredOrderId, studentId)).resolves.toMatchObject({ canSend: false, messages: [] });
  });

  it('never shows a third party any of it', async () => {
    await expect(service.history(activeOrderId, strangerId)).rejects.toThrow('Only this order’s student and runner');
    expect(await service.threads(strangerId)).toEqual([]);
  });
});
