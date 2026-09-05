/**
 * Real-Postgres proof of Task 21a's core correctness requirement: two
 * runners claiming the same order at the same instant must not both
 * "win" — exactly one must succeed, the other must get the distinct
 * ORDER_ALREADY_CLAIMED conflict. A mocked-Prisma unit test can assert the
 * right WHERE clause was constructed, but only a real database can prove
 * the race is actually closed — see order-escrow.db-constraint's own doc
 * comment for the same reasoning applied to hold()'s duplicate-escrow race.
 *
 * Skipped by default: `npm test` must not require a live database.
 *
 *   RUN_DB_INTEGRATION_TESTS=1 npx jest matching.claim.integration
 */
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'crypto';
import { JwtPayload } from '../src/auth/jwt-payload.interface';
import { OrderEscrowService } from '../src/order-escrow/order-escrow.service';
import { generateVerificationCode } from '../src/orders/pin-code.util';

const RUN = process.env.RUN_DB_INTEGRATION_TESTS === '1';
const describeIfDb = RUN ? describe : describe.skip;

function makeRealService(prisma: PrismaClient) {
  const paystack = { initiateTransfer: jest.fn() };
  const config = { get: jest.fn() };
  const notifications = { emit: jest.fn() };
  const matching = { broadcastNewJob: jest.fn(), cancelPendingJobs: jest.fn().mockResolvedValue(undefined) };
  const alerts = { send: jest.fn().mockResolvedValue(undefined) };
  return new OrderEscrowService(prisma as any, paystack as any, config as any, notifications as any, matching as any, alerts as any);
}

describeIfDb('OrderEscrowService.claim — real concurrent claim race', () => {
  const prisma = new PrismaClient();
  let studentId: string;
  let vendorUserId: string;
  let vendorId: string;
  let runnerAId: string;
  let runnerBId: string;
  let walletId: string;
  let orderId: string;

  beforeAll(async () => {
    studentId = randomUUID();
    vendorUserId = randomUUID();
    runnerAId = randomUUID();
    runnerBId = randomUUID();
    orderId = `t21a-order-${randomUUID()}`;

    await Promise.all([
      prisma.user.create({ data: { id: studentId, email: `t21a-student-${studentId}@test.internal`, accountType: 'student' } }),
      prisma.user.create({ data: { id: vendorUserId, email: `t21a-vendor-${vendorUserId}@test.internal`, accountType: 'restaurant' } }),
      prisma.user.create({ data: { id: runnerAId, phone: `+234700${runnerAId.slice(0, 7)}`, accountType: 'runner' } }),
      prisma.user.create({ data: { id: runnerBId, phone: `+234700${runnerBId.slice(0, 7)}`, accountType: 'runner' } }),
    ]);

    // Task 29: claim() hard-gates on an approved RunnerKyc row — both
    // runners need one or every claim below rejects on the gate itself,
    // never reaching the race this test actually proves.
    await Promise.all([
      prisma.runnerKyc.create({ data: { userId: runnerAId, status: 'approved' } }),
      prisma.runnerKyc.create({ data: { userId: runnerBId, status: 'approved' } }),
    ]);

    const [wallet, vendor] = await Promise.all([
      prisma.wallet.create({ data: { userId: studentId, balance: 1_000_000 } }),
      prisma.vendor.create({ data: { userId: vendorUserId, businessName: 'T21a throwaway vendor', category: 'Test' } }),
    ]);
    walletId = wallet.id;
    vendorId = vendor.id;

    // An order already "preparing" (restaurant-accepted) with no runner
    // attached — exactly the state a real broadcast fires from.
    await prisma.order.create({
      data: {
        id: orderId,
        studentUserId: studentId,
        vendorId,
        status: 'preparing',
        totalAmount: 10_000,
        pickupCode: generateVerificationCode(),
        deliveryPin: generateVerificationCode(),
      },
    });
    const walletTxn = await prisma.walletTransaction.create({
      data: { walletId, type: 'debit', amount: 10_000, reference: `t21a_ref_${randomUUID()}`, status: 'success' },
    });
    await prisma.orderEscrow.create({
      data: {
        orderId,
        studentWalletTransactionId: walletTxn.id,
        restaurantUserId: vendorUserId,
        runnerUserId: null,
        status: 'held',
        grossAmount: 10_000,
        platformFee: 1_500,
        restaurantShare: 8_000,
        runnerShare: 500,
        foodSubtotal: 10_000,
        restaurantCommission: 1_500,
        restaurantPlatformFee: 500,
      },
    });
  });

  afterAll(async () => {
    await prisma.orderEscrow.deleteMany({ where: { orderId } });
    await prisma.walletTransaction.deleteMany({ where: { walletId } });
    await prisma.order.delete({ where: { id: orderId } });
    await prisma.wallet.delete({ where: { id: walletId } });
    await prisma.vendor.delete({ where: { id: vendorId } });
    await prisma.runnerKyc.deleteMany({ where: { userId: { in: [runnerAId, runnerBId] } } });
    await prisma.user.deleteMany({ where: { id: { in: [studentId, vendorUserId, runnerAId, runnerBId] } } });
    await prisma.$disconnect();
  });

  it('lets exactly one of two simultaneous claims win, and the loser gets ORDER_ALREADY_CLAIMED', async () => {
    const service = makeRealService(prisma);
    const runnerA: JwtPayload = { sub: runnerAId, accountType: 'runner', role: 'user' };
    const runnerB: JwtPayload = { sub: runnerBId, accountType: 'runner', role: 'user' };

    // Genuinely concurrent — both requests fire before either has a chance
    // to observe the other's result. This is the actual race the
    // orderEscrow.updateMany's `WHERE runner_user_id IS NULL` clause has to
    // close at the database level, not application logic serializing them.
    const [resultA, resultB] = await Promise.allSettled([
      service.claim(orderId, runnerA),
      service.claim(orderId, runnerB),
    ]);

    const outcomes = [resultA, resultB];
    const fulfilled = outcomes.filter((r) => r.status === 'fulfilled');
    const rejected = outcomes.filter((r) => r.status === 'rejected');

    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);

    const rejection = (rejected[0] as PromiseRejectedResult).reason;
    expect(rejection.getResponse()).toMatchObject({ code: 'ORDER_ALREADY_CLAIMED' });

    // The database itself agrees: exactly one of the two runners actually
    // holds this order, and both the Order and OrderEscrow rows agree with
    // each other on who.
    const [finalOrder, finalEscrow] = await Promise.all([
      prisma.order.findUniqueOrThrow({ where: { id: orderId } }),
      prisma.orderEscrow.findUniqueOrThrow({ where: { orderId } }),
    ]);
    expect(finalOrder.runnerUserId).toBe(finalEscrow.runnerUserId);
    expect([runnerAId, runnerBId]).toContain(finalOrder.runnerUserId);
  });
});
