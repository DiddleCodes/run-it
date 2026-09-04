/**
 * Real-Postgres proof of Task 32's core correctness requirement — the same
 * class of race Task 21a's claim-race fix closed for order claims, applied
 * here to a wallet withdrawal debit instead: two concurrent withdrawal
 * requests for the same wallet, each for the full balance, must not both
 * succeed. A mocked-Prisma unit test (wallet.service.spec.ts) can assert
 * the right WHERE clause was constructed, but only a real database can
 * prove the race is actually closed — see order-escrow.db-constraint's own
 * doc comment for the same reasoning applied to hold()'s duplicate-escrow
 * race.
 *
 * Skipped by default: `npm test` must not require a live database.
 *
 *   RUN_DB_INTEGRATION_TESTS=1 npx jest wallet-withdraw-race
 */
import { HttpException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { randomUUID } from 'crypto';
import { WalletService } from '../src/wallet/wallet.service';

const RUN = process.env.RUN_DB_INTEGRATION_TESTS === '1';
const describeIfDb = RUN ? describe : describe.skip;

function makeRealService(prisma: PrismaClient) {
  // Paystack itself is deliberately stubbed, same choice
  // matching.claim.integration.spec.ts makes — the race this test proves
  // is entirely a database-level guarantee (the conditional wallet debit),
  // never reachable by more than one of the two concurrent calls here.
  const paystack = { initiateTransfer: jest.fn().mockResolvedValue({ reference: 'ref', transferCode: 'TRF_x', status: 'pending' }) };
  const webhooks = { applyVerifiedTransferResult: jest.fn() };
  const alerts = { send: jest.fn() };
  return new WalletService(prisma as any, paystack as any, webhooks as any, alerts as any);
}

describeIfDb('WalletService.initiateWithdrawal — real concurrent withdrawal race', () => {
  const prisma = new PrismaClient();
  let userId: string;
  let walletId: string;

  beforeAll(async () => {
    userId = randomUUID();

    await prisma.user.create({ data: { id: userId, email: `t32-student-${userId}@test.internal`, accountType: 'student' } });
    const wallet = await prisma.wallet.create({ data: { userId, balance: 10_000 } });
    walletId = wallet.id;
    await prisma.payoutAccount.create({
      data: {
        userId,
        bankCode: '058',
        accountNumber: '0123456789',
        accountName: 'T32 Throwaway Account',
        paystackRecipientCode: 'RCP_t32_throwaway',
      },
    });
  });

  afterAll(async () => {
    await prisma.walletTransaction.deleteMany({ where: { walletId } });
    await prisma.payoutAccount.deleteMany({ where: { userId } });
    await prisma.wallet.delete({ where: { id: walletId } });
    await prisma.user.delete({ where: { id: userId } });
    await prisma.$disconnect();
  });

  it('lets exactly one of two simultaneous full-balance withdrawals win, and the loser gets a clean insufficient-balance rejection', async () => {
    const service = makeRealService(prisma);

    // Genuinely concurrent — both requests fire before either has a chance
    // to observe the other's result. This is the actual race the wallet
    // updateMany's `WHERE balance >= amount` clause has to close at the
    // database level, not application logic serializing them.
    const [resultA, resultB] = await Promise.allSettled([
      service.initiateWithdrawal({ userId, amountKobo: 10_000 }),
      service.initiateWithdrawal({ userId, amountKobo: 10_000 }),
    ]);

    const outcomes = [resultA, resultB];
    const fulfilled = outcomes.filter((r) => r.status === 'fulfilled');
    const rejected = outcomes.filter((r) => r.status === 'rejected');

    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect((rejected[0] as PromiseRejectedResult).reason).toBeInstanceOf(HttpException);

    // The database itself agrees: the balance landed at exactly zero, never
    // negative — impossible if both debits had gone through.
    const finalWallet = await prisma.wallet.findUniqueOrThrow({ where: { id: walletId } });
    expect(finalWallet.balance).toBe(0);

    const withdrawalRows = await prisma.walletTransaction.findMany({ where: { walletId, type: 'debit' } });
    expect(withdrawalRows).toHaveLength(1);
  });
});
