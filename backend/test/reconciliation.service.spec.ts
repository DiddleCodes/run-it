import { ReconciliationService } from '../src/reconciliation/reconciliation.service';
import { createConfigMock, createPaystackMock, createPrismaMock } from './support/mocks';

const RECONCILE_CONFIG = {
  'reconciliation.intervalMinutes': 5,
  'reconciliation.staleThresholdMinutes': 10,
};

function makeService() {
  const prisma = createPrismaMock();
  const paystack = createPaystackMock();
  const config = createConfigMock(RECONCILE_CONFIG);
  const webhooks = {
    applyVerifiedChargeSuccess: jest.fn(),
    markChargeFailed: jest.fn(),
    applyVerifiedTransferResult: jest.fn(),
  };
  const alerts = { send: jest.fn() };
  const scheduler = { addCronJob: jest.fn() };
  const service = new ReconciliationService(
    config as any,
    prisma as any,
    paystack as any,
    webhooks as any,
    alerts as any,
    scheduler as any,
  );
  return { service, prisma, paystack, webhooks, alerts, scheduler };
}

const MINUTES_AGO = (n: number) => new Date(Date.now() - n * 60_000);

describe('ReconciliationService — stale wallet_transactions', () => {
  it('resolves a manually-inserted stale-pending row that actually succeeded on Paystack', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { id: 'wt-stale-1', reference: 'wallet_fund_stale', amount: 5_000, status: 'pending', createdAt: MINUTES_AGO(15) },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.verifyTransaction.mockResolvedValue({ status: 'success', amount: 5_000 });

    const result = await service.runReconciliation();

    expect(paystack.verifyTransaction).toHaveBeenCalledWith('wallet_fund_stale');
    expect(webhooks.applyVerifiedChargeSuccess).toHaveBeenCalledWith('wallet_fund_stale', 5_000);
    expect(webhooks.markChargeFailed).not.toHaveBeenCalled();
    expect(alerts.send).not.toHaveBeenCalled();
    expect(result.walletChecked).toBe(1);
  });

  it('marks a stale row failed and alerts when Paystack reports it as failed/abandoned', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { id: 'wt-stale-2', reference: 'wallet_fund_stale2', amount: 5_000, status: 'pending', createdAt: MINUTES_AGO(20) },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.verifyTransaction.mockResolvedValue({ status: 'abandoned', amount: 5_000 });

    await service.runReconciliation();

    expect(webhooks.markChargeFailed).toHaveBeenCalledWith('wallet_fund_stale2');
    expect(alerts.send).toHaveBeenCalledWith(expect.stringContaining('abandoned'), expect.any(Object));
  });

  it('alerts (without applying anything) when the transaction is still genuinely pending on Paystack', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { id: 'wt-stale-3', reference: 'wallet_fund_stale3', amount: 5_000, status: 'pending', createdAt: MINUTES_AGO(30) },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.verifyTransaction.mockResolvedValue({ status: 'pending', amount: 5_000 });

    await service.runReconciliation();

    expect(webhooks.applyVerifiedChargeSuccess).not.toHaveBeenCalled();
    expect(webhooks.markChargeFailed).not.toHaveBeenCalled();
    expect(alerts.send).toHaveBeenCalledWith(expect.stringContaining('still pending'), expect.any(Object));
  });

  it('alerts (does not crash the sweep) when the Paystack verify call itself fails', async () => {
    const { service, prisma, paystack, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { id: 'wt-stale-4', reference: 'wallet_fund_stale4', amount: 5_000, status: 'pending', createdAt: MINUTES_AGO(15) },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.verifyTransaction.mockRejectedValue(new Error('Paystack unreachable'));

    await expect(service.runReconciliation()).resolves.toBeDefined();
    expect(alerts.send).toHaveBeenCalledWith(
      expect.stringContaining('failed to verify'),
      expect.objectContaining({ error: 'Paystack unreachable' }),
    );
  });

  it('does not touch a pending row that is not yet past the staleness threshold', async () => {
    const { service, prisma } = makeService();
    // The query itself filters on createdAt < staleBefore — assert the
    // service actually applies that filter rather than fetching everything.
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);

    await service.runReconciliation();

    const callArgs = prisma.walletTransaction.findMany.mock.calls[0][0];
    expect(callArgs.where.status).toBe('pending');
    expect(callArgs.where.createdAt.lt.getTime()).toBeLessThanOrEqual(Date.now() - 10 * 60_000 + 1000);
  });
});

describe('ReconciliationService — stale escrow transfer legs', () => {
  it('resolves a stuck runner leg that succeeded on Paystack', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([
      {
        id: 'esc1',
        orderId: 'order-1',
        restaurantTransferReference: 'escrow_esc1_restaurant',
        restaurantTransferStatus: 'success',
        runnerTransferReference: 'escrow_esc1_runner',
        runnerTransferStatus: 'pending',
        releasedAt: MINUTES_AGO(20),
      },
    ]);
    paystack.verifyTransferStatus.mockResolvedValue({ status: 'success' });

    const result = await service.runReconciliation();

    expect(paystack.verifyTransferStatus).toHaveBeenCalledWith('escrow_esc1_runner');
    expect(webhooks.applyVerifiedTransferResult).toHaveBeenCalledWith('escrow_esc1_runner', 'success');
    expect(alerts.send).not.toHaveBeenCalled();
    expect(result.transferLegsChecked).toBe(1);
  });

  it('alerts on a transfer that resolves as failed/reversed via reconciliation', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([
      {
        id: 'esc2',
        orderId: 'order-2',
        restaurantTransferReference: 'escrow_esc2_restaurant',
        restaurantTransferStatus: 'pending',
        runnerTransferReference: null,
        runnerTransferStatus: 'not_applicable',
        releasedAt: MINUTES_AGO(20),
      },
    ]);
    paystack.verifyTransferStatus.mockResolvedValue({ status: 'reversed' });

    await service.runReconciliation();

    expect(webhooks.applyVerifiedTransferResult).toHaveBeenCalledWith('escrow_esc2_restaurant', 'failed');
    expect(alerts.send).toHaveBeenCalledWith(expect.stringContaining('reversed'), expect.objectContaining({ orderId: 'order-2' }));
  });

  it('alerts on a leg still stuck pending on Paystack past the threshold, with no resolution', async () => {
    const { service, prisma, paystack, webhooks, alerts } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([
      {
        id: 'esc3',
        orderId: 'order-3',
        restaurantTransferReference: 'escrow_esc3_restaurant',
        restaurantTransferStatus: 'pending',
        runnerTransferReference: null,
        runnerTransferStatus: 'not_applicable',
        releasedAt: MINUTES_AGO(25),
      },
    ]);
    paystack.verifyTransferStatus.mockResolvedValue({ status: 'pending' });

    await service.runReconciliation();

    expect(webhooks.applyVerifiedTransferResult).not.toHaveBeenCalled();
    expect(alerts.send).toHaveBeenCalledWith(
      expect.stringContaining('still pending'),
      expect.objectContaining({ orderId: 'order-3' }),
    );
  });
});

describe('ReconciliationService.runReconciliation — run history', () => {
  it('persists one ReconciliationRun row per invocation, recording who triggered it', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);

    await service.runReconciliation('admin-1');

    expect(prisma.reconciliationRun.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ walletChecked: 0, transferLegsChecked: 0, triggeredBy: 'admin-1' }),
      }),
    );
  });

  it('records triggeredBy as undefined for the scheduled cron (no admin behind it)', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);

    await service.runReconciliation();

    expect(prisma.reconciliationRun.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ triggeredBy: undefined }) }),
    );
  });

  it('does not let a compareAgainstPaystack failure crash the run or block the run row from being written', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.listTransactions.mockRejectedValue(new Error('Paystack unreachable'));

    await expect(service.runReconciliation()).resolves.toBeDefined();
    expect(prisma.reconciliationRun.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ mismatchCount: 0 }) }),
    );
  });
});

describe('ReconciliationService.compareAgainstPaystack', () => {
  it('flags a Paystack transaction with no local WalletTransaction row as missing_locally', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.listTransactions.mockResolvedValue({
      items: [{ reference: 'wallet_fund_ghost', amount: 5_000, status: 'success', paidAt: null }],
      page: 1,
      pageCount: 1,
    });

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.summary.missingLocally).toBe(1);
    expect(result.mismatches[0]).toEqual(
      expect.objectContaining({ reference: 'wallet_fund_ghost', kind: 'missing_locally', type: 'wallet_topup' }),
    );
  });

  it('flags a local success row with nothing on Paystack as missing_on_paystack', async () => {
    const { service, prisma } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { reference: 'wallet_fund_orphan', amount: 3_000, status: 'success', createdAt: new Date() },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.summary.missingOnPaystack).toBe(1);
    expect(result.mismatches[0].kind).toBe('missing_on_paystack');
  });

  it('flags a same-reference amount disagreement as amount_mismatch', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { reference: 'wallet_fund_x', amount: 5_000, status: 'success', createdAt: new Date() },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.listTransactions.mockResolvedValue({
      items: [{ reference: 'wallet_fund_x', amount: 4_500, status: 'success', paidAt: null }],
      page: 1,
      pageCount: 1,
    });

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.summary.amountMismatch).toBe(1);
  });

  it('excludes a genuinely matched reference from the returned mismatches list, but counts it', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([
      { reference: 'wallet_fund_ok', amount: 5_000, status: 'success', createdAt: new Date() },
    ]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.listTransactions.mockResolvedValue({
      items: [{ reference: 'wallet_fund_ok', amount: 5_000, status: 'success', paidAt: null }],
      page: 1,
      pageCount: 1,
    });

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.summary.matched).toBe(1);
    expect(result.mismatches).toHaveLength(0);
  });

  it('also compares successful escrow transfer legs against Paystack transfer list', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([
      {
        restaurantTransferReference: 'escrow_1_restaurant',
        restaurantTransferStatus: 'success',
        restaurantShare: 4_000,
        runnerTransferReference: null,
        runnerTransferStatus: 'not_applicable',
        runnerShare: 0,
        createdAt: new Date(),
      },
    ]);
    paystack.listTransfers.mockResolvedValue({ items: [], page: 1, pageCount: 1 });

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.mismatches).toEqual([
      expect.objectContaining({ reference: 'escrow_1_restaurant', type: 'transfer', kind: 'missing_on_paystack' }),
    ]);
  });

  it('marks a mismatch resolved: true when a ReconciliationResolution row exists for that reference', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.walletTransaction.findMany.mockResolvedValue([]);
    prisma.orderEscrow.findMany.mockResolvedValue([]);
    paystack.listTransactions.mockResolvedValue({
      items: [{ reference: 'wallet_fund_known_issue', amount: 5_000, status: 'success', paidAt: null }],
      page: 1,
      pageCount: 1,
    });
    prisma.reconciliationResolution.findMany.mockResolvedValue([{ reference: 'wallet_fund_known_issue' }]);

    const result = await service.compareAgainstPaystack(new Date(0), new Date());

    expect(result.mismatches[0].resolved).toBe(true);
  });
});

describe('ReconciliationService.resolveMismatch', () => {
  it('upserts a ReconciliationResolution row keyed by reference', async () => {
    const { service, prisma } = makeService();
    prisma.reconciliationResolution.upsert.mockResolvedValue({ reference: 'ref-1' });

    await service.resolveMismatch('ref-1', 'admin-1', 'Known Paystack indexing delay, confirmed manually');

    expect(prisma.reconciliationResolution.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { reference: 'ref-1' },
        create: expect.objectContaining({ reference: 'ref-1', resolvedBy: 'admin-1' }),
      }),
    );
  });
});
