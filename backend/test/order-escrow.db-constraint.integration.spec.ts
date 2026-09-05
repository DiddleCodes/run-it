/**
 * Real-Postgres proof that a duplicate hold for the same orderId is
 * rejected by the DATABASE, not just by OrderEscrowService's own
 * pre-check — Task 9b explicitly calls this out separately from the
 * application-logic test in order-escrow.service.spec.ts.
 *
 * Skipped by default: `npm test` must not require a live database (see
 * README). Run explicitly against a real Postgres pointed at by
 * DATABASE_URL:
 *
 *   RUN_DB_INTEGRATION_TESTS=1 npx jest order-escrow.db-constraint
 *
 * See RUNBOOK.md for what this actually proves and why it matters.
 */
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'crypto';

const RUN = process.env.RUN_DB_INTEGRATION_TESTS === '1';
const describeIfDb = RUN ? describe : describe.skip;

describeIfDb('order_escrows.order_id — real DB unique constraint', () => {
  const prisma = new PrismaClient();
  let studentId: string;
  let vendorUserId: string;
  let vendorId: string;
  let walletId: string;
  let walletTxnAId: string;
  let walletTxnBId: string;

  beforeAll(async () => {
    studentId = randomUUID();
    vendorUserId = randomUUID();

    await prisma.user.create({ data: { id: studentId, email: `t9b-student-${studentId}@test.internal`, accountType: 'student' } });
    await prisma.user.create({ data: { id: vendorUserId, email: `t9b-vendor-${vendorUserId}@test.internal`, accountType: 'restaurant' } });

    const [wallet, vendor] = await Promise.all([
      prisma.wallet.create({ data: { userId: studentId, balance: 100_000 } }),
      prisma.vendor.create({ data: { userId: vendorUserId, businessName: 'T9b throwaway vendor', category: 'Test' } }),
    ]);
    walletId = wallet.id;
    vendorId = vendor.id;

    // Two distinct wallet_transactions, since order_escrows also uniquely
    // constrains student_wallet_transaction_id — this test is only about
    // proving order_id's own constraint, so the two attempted inserts must
    // differ on every *other* unique column.
    const [a, b] = await Promise.all([
      prisma.walletTransaction.create({
        data: { walletId, type: 'debit', amount: 1000, reference: `t9b_ref_a_${randomUUID()}`, status: 'success' },
      }),
      prisma.walletTransaction.create({
        data: { walletId, type: 'debit', amount: 1000, reference: `t9b_ref_b_${randomUUID()}`, status: 'success' },
      }),
    ]);
    walletTxnAId = a.id;
    walletTxnBId = b.id;
  });

  afterAll(async () => {
    await prisma.walletTransaction.deleteMany({ where: { id: { in: [walletTxnAId, walletTxnBId] } } });
    await prisma.wallet.delete({ where: { id: walletId } });
    await prisma.vendor.delete({ where: { id: vendorId } });
    await prisma.user.deleteMany({ where: { id: { in: [studentId, vendorUserId] } } });
    await prisma.$disconnect();
  });

  it('rejects a second INSERT for the same order_id even when nothing in application code checks first', async () => {
    const orderId = `t9b-order-${randomUUID()}`;
    // A real Order row is required first — order_escrows.order_id is a hard
    // FK into orders.id (see OrderEscrow's schema doc comment).
    await prisma.order.create({
      data: {
        id: orderId,
        studentUserId: studentId,
        vendorId,
        status: 'placed',
        totalAmount: 1000,
        pickupCode: '1234',
        deliveryPin: '5678',
      },
    });

    const create = (walletTransactionId: string) =>
      prisma.orderEscrow.create({
        data: {
          orderId,
          studentWalletTransactionId: walletTransactionId,
          restaurantUserId: vendorUserId,
          runnerUserId: studentId,
          status: 'held',
          grossAmount: 1000,
          platformFee: 150,
          restaurantShare: 700,
          runnerShare: 150,
          foodSubtotal: 1000,
          restaurantCommission: 150,
          restaurantPlatformFee: 150,
        },
      });

    // Deliberately bypasses OrderEscrowService's findUnique pre-check
    // entirely — this calls Prisma directly, twice, for the same orderId.
    // If application logic were the only thing preventing a duplicate, both
    // calls below would succeed.
    await create(walletTxnAId);
    await expect(create(walletTxnBId)).rejects.toThrow(/Unique constraint/i);

    const rows = await prisma.orderEscrow.findMany({ where: { orderId } });
    expect(rows).toHaveLength(1);

    await prisma.orderEscrow.deleteMany({ where: { orderId } });
    await prisma.order.delete({ where: { id: orderId } });
  });
});
