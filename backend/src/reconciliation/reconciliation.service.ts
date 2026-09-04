import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SchedulerRegistry } from '@nestjs/schedule';
import { CronJob } from 'cron';
import { AlertsService } from '../alerts/alerts.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';

const RECONCILIATION_JOB_NAME = 'payments-reconciliation';

/**
 * Self-healing sweep for lost/never-delivered Paystack webhooks. This is
 * deliberately *not* just an alerting job: on every run it actively calls
 * Paystack's verify-transaction / verify-transfer endpoints for anything
 * stuck `pending` past the configured threshold and applies the result
 * through the exact same idempotent DB paths the webhooks themselves use
 * (WebhooksService.applyVerifiedChargeSuccess / applyVerifiedTransferResult)
 * — so a lost webhook resolves itself within one sweep interval instead of
 * leaving money in limbo until someone notices.
 */
@Injectable()
export class ReconciliationService implements OnModuleInit {
  private readonly logger = new Logger(ReconciliationService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly webhooks: WebhooksService,
    private readonly alerts: AlertsService,
    private readonly scheduler: SchedulerRegistry,
  ) {}

  onModuleInit(): void {
    const intervalMinutes = this.config.get<number>('reconciliation.intervalMinutes') as number;
    const job = new CronJob(`0 */${intervalMinutes} * * * *`, () => {
      this.runReconciliation().catch((err) => {
        this.logger.error(`Reconciliation sweep crashed: ${(err as Error).message}`);
      });
    });
    this.scheduler.addCronJob(RECONCILIATION_JOB_NAME, job);
    job.start();
    this.logger.log(`Reconciliation sweep scheduled every ${intervalMinutes} minute(s)`);
  }

  // Task 13c: persists one ReconciliationRun row per invocation (both the
  // scheduled cron above and the new admin-triggered manual run funnel
  // through this one method) — this is what makes "a log of past
  // reconciliation runs" real rather than log-only. mismatchCount comes
  // from compareAgainstPaystack() over the same window the sweep just
  // covered, so the run log reflects the read-only comparison view too,
  // not just the self-healing counts.
  async runReconciliation(triggeredBy?: string): Promise<{ walletChecked: number; transferLegsChecked: number }> {
    const startedAt = new Date();
    const thresholdMinutes = this.config.get<number>('reconciliation.staleThresholdMinutes') as number;
    const staleBefore = new Date(Date.now() - thresholdMinutes * 60_000);

    const [walletChecked, transferLegsChecked, withdrawalsChecked] = await Promise.all([
      this.reconcileWalletTransactions(staleBefore),
      this.reconcileTransferLegs(staleBefore),
      this.reconcileWithdrawalTransfers(staleBefore),
    ]);

    const mismatchCount = await this.compareAgainstPaystack(staleBefore, new Date())
      .then((r) => r.summary.missingLocally + r.summary.missingOnPaystack + r.summary.amountMismatch + r.summary.statusMismatch)
      .catch((err) => {
        this.logger.error(`compareAgainstPaystack failed during run logging: ${(err as Error).message}`);
        return 0;
      });

    // Task 32: withdrawal transfers folded into the same transferLegsChecked
    // count rather than a new ReconciliationRun column — a withdrawal is
    // just another transfer leg on the same Paystack Transfers API,
    // reconciled through the exact same verify-transfer-status call.
    const totalTransferLegsChecked = transferLegsChecked + withdrawalsChecked;

    await this.prisma.reconciliationRun.create({
      data: {
        startedAt,
        finishedAt: new Date(),
        walletChecked,
        transferLegsChecked: totalTransferLegsChecked,
        mismatchCount,
        triggeredBy,
      },
    });

    return { walletChecked, transferLegsChecked: totalTransferLegsChecked };
  }

  async listRuns() {
    return this.prisma.reconciliationRun.findMany({ orderBy: { startedAt: 'desc' }, take: 50 });
  }

  // Read-only comparison — distinct from the self-healing sweep above,
  // which only ever looks at rows that already exist locally and are
  // stuck pending. This is the one thing that sweep structurally can't
  // catch: a Paystack-recorded charge or transfer with NO local row at
  // all. Pulls Paystack's real transaction/transfer lists for the range
  // (paginated) and diffs by reference against local WalletTransaction
  // (successful charges) and OrderEscrow transfer legs (successful
  // transfers).
  async compareAgainstPaystack(from: Date, to: Date) {
    const [localCharges, localEscrows, paystackTx, paystackTransfers, resolutions] = await Promise.all([
      this.prisma.walletTransaction.findMany({ where: { status: 'success', createdAt: { gte: from, lte: to } } }),
      this.prisma.orderEscrow.findMany({ where: { createdAt: { gte: from, lte: to } } }),
      this.fetchAllPages((page) => this.paystack.listTransactions({ from: from.toISOString(), to: to.toISOString(), page })),
      this.fetchAllPages((page) => this.paystack.listTransfers({ from: from.toISOString(), to: to.toISOString(), page })),
      this.prisma.reconciliationResolution.findMany(),
    ]);

    const resolvedRefs = new Set(resolutions.map((r) => r.reference));

    const localChargeMap = new Map(localCharges.map((c) => [c.reference, { amount: c.amount, status: 'success' }]));
    const localTransferMap = new Map<string, { amount: number; status: string }>();
    for (const escrow of localEscrows) {
      if (escrow.restaurantTransferReference && escrow.restaurantTransferStatus === 'success') {
        localTransferMap.set(escrow.restaurantTransferReference, { amount: escrow.restaurantShare, status: 'success' });
      }
      if (escrow.runnerTransferReference && escrow.runnerTransferStatus === 'success') {
        localTransferMap.set(escrow.runnerTransferReference, { amount: escrow.runnerShare, status: 'success' });
      }
    }

    const paystackTxMap = new Map(paystackTx.map((t) => [t.reference, { amount: t.amount, status: t.status }]));
    const paystackTransferMap = new Map(paystackTransfers.map((t) => [t.reference, { amount: t.amount, status: t.status }]));

    const mismatches = [
      ...this.diffOneType('wallet_topup', localChargeMap, paystackTxMap, resolvedRefs),
      ...this.diffOneType('transfer', localTransferMap, paystackTransferMap, resolvedRefs),
    ];

    const summary = {
      matched: mismatches.filter((m) => m.kind === 'matched').length,
      missingLocally: mismatches.filter((m) => m.kind === 'missing_locally').length,
      missingOnPaystack: mismatches.filter((m) => m.kind === 'missing_on_paystack').length,
      amountMismatch: mismatches.filter((m) => m.kind === 'amount_mismatch').length,
      statusMismatch: mismatches.filter((m) => m.kind === 'status_mismatch').length,
    };

    // The report only needs to show real problems, not every matched row.
    return { from, to, summary, mismatches: mismatches.filter((m) => m.kind !== 'matched') };
  }

  async resolveMismatch(reference: string, resolvedBy: string, note: string) {
    return this.prisma.reconciliationResolution.upsert({
      where: { reference },
      create: { reference, resolvedBy, note },
      update: { resolvedBy, note, resolvedAt: new Date() },
    });
  }

  private diffOneType(
    type: 'wallet_topup' | 'transfer',
    local: Map<string, { amount: number; status: string }>,
    remote: Map<string, { amount: number; status: string }>,
    resolvedRefs: Set<string>,
  ) {
    const results: {
      reference: string;
      type: 'wallet_topup' | 'transfer';
      kind: 'matched' | 'missing_locally' | 'missing_on_paystack' | 'amount_mismatch' | 'status_mismatch';
      localAmount: number | null;
      paystackAmount: number | null;
      localStatus: string | null;
      paystackStatus: string | null;
      resolved: boolean;
    }[] = [];

    const allRefs = new Set([...local.keys(), ...remote.keys()]);
    for (const reference of allRefs) {
      const l = local.get(reference);
      const r = remote.get(reference);
      const resolved = resolvedRefs.has(reference);

      if (l && !r) {
        results.push({ reference, type, kind: 'missing_on_paystack', localAmount: l.amount, paystackAmount: null, localStatus: l.status, paystackStatus: null, resolved });
      } else if (!l && r) {
        results.push({ reference, type, kind: 'missing_locally', localAmount: null, paystackAmount: r.amount, localStatus: null, paystackStatus: r.status, resolved });
      } else if (l && r) {
        if (l.amount !== r.amount) {
          results.push({ reference, type, kind: 'amount_mismatch', localAmount: l.amount, paystackAmount: r.amount, localStatus: l.status, paystackStatus: r.status, resolved });
        } else if (r.status !== 'success') {
          results.push({ reference, type, kind: 'status_mismatch', localAmount: l.amount, paystackAmount: r.amount, localStatus: l.status, paystackStatus: r.status, resolved });
        } else {
          results.push({ reference, type, kind: 'matched', localAmount: l.amount, paystackAmount: r.amount, localStatus: l.status, paystackStatus: r.status, resolved });
        }
      }
    }
    return results;
  }

  // Caps at 20 pages (2,000 records at 100/page) — a sane safety bound so
  // a malformed Paystack `meta.pageCount` can never turn this into an
  // unbounded loop against a real HTTP API.
  private async fetchAllPages<T extends { reference: string; amount: number; status: string }>(
    fetchPage: (page: number) => Promise<{ items: T[]; page: number; pageCount: number }>,
  ): Promise<T[]> {
    const MAX_PAGES = 20;
    const first = await fetchPage(1);
    const items = [...first.items];
    const pageCount = Math.min(first.pageCount, MAX_PAGES);
    for (let page = 2; page <= pageCount; page++) {
      const next = await fetchPage(page);
      items.push(...next.items);
    }
    return items;
  }

  private async reconcileWalletTransactions(staleBefore: Date): Promise<number> {
    // Task 32: scoped to `credit` explicitly now that a `debit` row can
    // also be `pending` (a wallet withdrawal, mid-transfer — see
    // reconcileWithdrawalTransfers below) — without this, a stale
    // withdrawal would be swept up here too and checked against
    // verifyTransaction (the charge-verify endpoint), which is the wrong
    // Paystack API for a transfer reference.
    const stale = await this.prisma.walletTransaction.findMany({
      where: { type: 'credit', status: 'pending', createdAt: { lt: staleBefore } },
    });

    for (const txn of stale) {
      const ageMinutes = Math.round((Date.now() - txn.createdAt.getTime()) / 60_000);
      try {
        const result = await this.paystack.verifyTransaction(txn.reference);

        if (result.status === 'success') {
          await this.webhooks.applyVerifiedChargeSuccess(txn.reference, result.amount);
          this.logger.log(`Reconciled stale wallet_transaction ${txn.reference} -> success`);
        } else if (result.status === 'failed' || result.status === 'abandoned') {
          await this.webhooks.markChargeFailed(txn.reference);
          await this.alerts.send(`Wallet top-up ${txn.reference} resolved as '${result.status}' via reconciliation`, {
            walletTransactionId: txn.id,
            reference: txn.reference,
            ageMinutes,
          });
        } else {
          // Genuinely still pending on Paystack's side past our own
          // threshold — nothing to apply, but worth a human look.
          await this.alerts.send(`Wallet top-up ${txn.reference} still pending on Paystack past the reconciliation threshold`, {
            walletTransactionId: txn.id,
            reference: txn.reference,
            ageMinutes,
            paystackStatus: result.status,
          });
        }
      } catch (err) {
        this.logger.error(`Reconciliation verify-transaction failed for ${txn.reference}: ${(err as Error).message}`);
        await this.alerts.send(`Reconciliation failed to verify wallet_transaction ${txn.reference}`, {
          walletTransactionId: txn.id,
          reference: txn.reference,
          ageMinutes,
          error: (err as Error).message,
        });
      }
    }

    return stale.length;
  }

  private async reconcileTransferLegs(staleBefore: Date): Promise<number> {
    const stale = await this.prisma.orderEscrow.findMany({
      where: {
        status: 'released',
        releasedAt: { lt: staleBefore },
        OR: [{ restaurantTransferStatus: 'pending' }, { runnerTransferStatus: 'pending' }],
      },
    });

    let checked = 0;
    for (const escrow of stale) {
      const legsToCheck: { leg: 'restaurant' | 'runner'; reference: string | null; status: string }[] = [
        { leg: 'restaurant', reference: escrow.restaurantTransferReference, status: escrow.restaurantTransferStatus },
        { leg: 'runner', reference: escrow.runnerTransferReference, status: escrow.runnerTransferStatus },
      ];

      for (const { leg, reference, status } of legsToCheck) {
        if (status !== 'pending' || !reference) continue;
        checked += 1;
        const ageMinutes = escrow.releasedAt
          ? Math.round((Date.now() - escrow.releasedAt.getTime()) / 60_000)
          : undefined;

        try {
          const result = await this.paystack.verifyTransferStatus(reference);

          if (result.status === 'success') {
            await this.webhooks.applyVerifiedTransferResult(reference, 'success');
            this.logger.log(`Reconciled stale transfer leg ${reference} -> success`);
          } else if (result.status === 'failed' || result.status === 'reversed') {
            await this.webhooks.applyVerifiedTransferResult(reference, 'failed');
            await this.alerts.send(
              `Order ${escrow.orderId} ${leg} transfer resolved as '${result.status}' via reconciliation`,
              { orderId: escrow.orderId, escrowId: escrow.id, leg, reference, ageMinutes },
            );
          } else {
            await this.alerts.send(`Order ${escrow.orderId} ${leg} transfer still pending on Paystack past threshold`, {
              orderId: escrow.orderId,
              escrowId: escrow.id,
              leg,
              reference,
              ageMinutes,
              paystackStatus: result.status,
            });
          }
        } catch (err) {
          this.logger.error(`Reconciliation verify-transfer failed for ${reference}: ${(err as Error).message}`);
          await this.alerts.send(`Reconciliation failed to verify transfer ${reference} (order ${escrow.orderId}, ${leg} leg)`, {
            orderId: escrow.orderId,
            escrowId: escrow.id,
            leg,
            reference,
            error: (err as Error).message,
          });
        }
      }
    }

    return checked;
  }

  // Task 32: the withdrawal counterpart to reconcileTransferLegs above —
  // same self-healing shape, applied to WalletService.initiateWithdrawal's
  // transfers instead of escrow payout legs. A withdrawal is the only
  // debit-type WalletTransaction ever created `pending` (see
  // WebhooksService.applyVerifiedWithdrawalResult's own doc comment), so
  // this query can't accidentally sweep up an escrow_hold debit.
  private async reconcileWithdrawalTransfers(staleBefore: Date): Promise<number> {
    const stale = await this.prisma.walletTransaction.findMany({
      where: { type: 'debit', status: 'pending', createdAt: { lt: staleBefore } },
    });

    for (const txn of stale) {
      const ageMinutes = Math.round((Date.now() - txn.createdAt.getTime()) / 60_000);
      try {
        const result = await this.paystack.verifyTransferStatus(txn.reference);

        if (result.status === 'success') {
          await this.webhooks.applyVerifiedTransferResult(txn.reference, 'success');
          this.logger.log(`Reconciled stale withdrawal ${txn.reference} -> success`);
        } else if (result.status === 'failed' || result.status === 'reversed') {
          await this.webhooks.applyVerifiedTransferResult(txn.reference, 'failed');
          await this.alerts.send(`Wallet withdrawal ${txn.reference} resolved as '${result.status}' via reconciliation`, {
            walletTransactionId: txn.id,
            reference: txn.reference,
            ageMinutes,
          });
        } else {
          await this.alerts.send(`Wallet withdrawal ${txn.reference} still pending on Paystack past the reconciliation threshold`, {
            walletTransactionId: txn.id,
            reference: txn.reference,
            ageMinutes,
            paystackStatus: result.status,
          });
        }
      } catch (err) {
        this.logger.error(`Reconciliation verify-transfer failed for withdrawal ${txn.reference}: ${(err as Error).message}`);
        await this.alerts.send(`Reconciliation failed to verify wallet withdrawal ${txn.reference}`, {
          walletTransactionId: txn.id,
          reference: txn.reference,
          ageMinutes,
          error: (err as Error).message,
        });
      }
    }

    return stale.length;
  }
}
