import { WebhooksService } from '../src/webhooks/webhooks.service';
import { createPrismaMock, createRedisMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const redis = createRedisMock();
  const service = new WebhooksService(prisma as any, redis as any);
  return { service, prisma, redis };
}

const chargeSuccessEvent = {
  event: 'charge.success' as const,
  data: {
    reference: 'wallet_fund_abc123',
    amount: 5_000,
    status: 'success',
    customer: { email: 'student@example.com' },
    metadata: { purpose: 'wallet_topup', userId: 'student-1' },
  },
};

describe('WebhooksService.applyPaystackEvent — charge.success idempotency', () => {
  it('credits the wallet exactly once even when the same reference is delivered twice', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findUnique.mockResolvedValue({
      id: 'wt1',
      walletId: 'w1',
      amount: 5_000,
      reference: 'wallet_fund_abc123',
      status: 'pending',
    });
    // First delivery: the conditional update actually flips the row.
    prisma.walletTransaction.updateMany.mockResolvedValueOnce({ count: 1 });
    // Second (duplicate) delivery: row is no longer pending, so it matches nothing.
    prisma.walletTransaction.updateMany.mockResolvedValueOnce({ count: 0 });

    await service.applyPaystackEvent(chargeSuccessEvent as any);
    await service.applyPaystackEvent(chargeSuccessEvent as any);

    expect(prisma.wallet.update).toHaveBeenCalledTimes(1);
    expect(prisma.wallet.update).toHaveBeenCalledWith({
      where: { id: 'w1' },
      data: { balance: { increment: 5_000 } },
    });
  });

  it('short-circuits on the Redis dedupe cache without touching the database at all', async () => {
    const { service, prisma, redis } = makeService();
    redis.wasAlreadyProcessed.mockResolvedValue(true);

    const result = await service.applyPaystackEvent(chargeSuccessEvent as any);

    expect(result).toEqual({ duplicate: true });
    expect(prisma.walletTransaction.findUnique).not.toHaveBeenCalled();
    expect(prisma.walletTransaction.updateMany).not.toHaveBeenCalled();
  });

  it('ignores charge.success events whose metadata is not a wallet top-up', async () => {
    const { service, prisma } = makeService();
    const otherEvent = { ...chargeSuccessEvent, data: { ...chargeSuccessEvent.data, metadata: { purpose: 'something_else' } } };

    await service.applyPaystackEvent(otherEvent as any);

    expect(prisma.walletTransaction.findUnique).not.toHaveBeenCalled();
  });

  it('does not credit anything for an unknown reference', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findUnique.mockResolvedValue(null);

    await service.applyPaystackEvent(chargeSuccessEvent as any);

    expect(prisma.walletTransaction.updateMany).not.toHaveBeenCalled();
    expect(prisma.wallet.update).not.toHaveBeenCalled();
  });
});

describe('WebhooksService.applyPaystackEvent — transfer confirmation', () => {
  it('updates only the matching leg on transfer.success, idempotently', async () => {
    const { service, prisma } = makeService();
    const escrow = {
      id: 'esc1',
      restaurantTransferReference: 'escrow_esc1_restaurant',
      runnerTransferReference: 'escrow_esc1_runner',
    };
    prisma.orderEscrow.findFirst.mockResolvedValue(escrow);
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });

    const transferEvent = {
      event: 'transfer.success' as const,
      data: { reference: 'escrow_esc1_restaurant', transfer_code: 'TRF_1', amount: 7_000, status: 'success' },
    };

    await service.applyPaystackEvent(transferEvent as any);

    expect(prisma.orderEscrow.updateMany).toHaveBeenCalledWith({
      where: { id: 'esc1', restaurantTransferStatus: 'pending' },
      data: { restaurantTransferStatus: 'success' },
    });
  });
});

// These are called directly by ReconciliationService, independent of any
// webhook delivery — verified separately here since that's their real
// second caller, not just an implementation detail of applyPaystackEvent.
describe('WebhooksService — reconciliation entry points', () => {
  it('applyVerifiedChargeSuccess is idempotent against a repeat call for an already-settled transaction', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findUnique.mockResolvedValue({
      id: 'wt1',
      walletId: 'w1',
      amount: 5_000,
      reference: 'ref1',
      status: 'success',
    });
    prisma.walletTransaction.updateMany.mockResolvedValue({ count: 0 });

    await service.applyVerifiedChargeSuccess('ref1', 5_000);

    expect(prisma.wallet.update).not.toHaveBeenCalled();
  });

  it('markChargeFailed only transitions a still-pending row', async () => {
    const { service, prisma } = makeService();

    await service.markChargeFailed('ref1');

    expect(prisma.walletTransaction.updateMany).toHaveBeenCalledWith({
      where: { reference: 'ref1', status: 'pending' },
      data: { status: 'failed' },
    });
  });

  it('applyVerifiedTransferResult updates the runner leg when the reference matches it', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findFirst.mockResolvedValue({
      id: 'esc1',
      restaurantTransferReference: 'escrow_esc1_restaurant',
      runnerTransferReference: 'escrow_esc1_runner',
    });

    await service.applyVerifiedTransferResult('escrow_esc1_runner', 'failed');

    expect(prisma.orderEscrow.updateMany).toHaveBeenCalledWith({
      where: { id: 'esc1', runnerTransferStatus: 'pending' },
      data: { runnerTransferStatus: 'failed' },
    });
  });
});
