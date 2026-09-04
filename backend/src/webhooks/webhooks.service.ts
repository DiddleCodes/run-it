import { Injectable, Logger } from '@nestjs/common';
import { WalletTransaction } from '@prisma/client';
import { PaystackChargeSuccessEvent, PaystackTransferEvent, PaystackWebhookEvent } from '../paystack/paystack.types';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

type TransferLegResult = 'success' | 'failed';

@Injectable()
export class WebhooksService {
  private readonly logger = new Logger(WebhooksService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  /**
   * The idempotent, DB-mutating half of webhook handling. Called by
   * WebhooksProcessor once a job is dequeued — signature verification
   * already happened synchronously in the controller before the event was
   * enqueued, so there's no rawBody here (BullMQ jobs are JSON, not raw
   * bytes) and none is needed.
   *
   * Safe to call more than once for the same event: the Redis dedupe check
   * below is a fast-path optimisation, but the real guarantee is the
   * per-branch DB-level conditional update (see applyVerifiedChargeSuccess /
   * applyVerifiedTransferResult) — the same guarantee that makes it safe for
   * ReconciliationService to call those two methods directly, independent
   * of any webhook delivery at all.
   */
  async applyPaystackEvent(body: PaystackWebhookEvent): Promise<{ duplicate: boolean }> {
    const reference = (body.data as { reference?: string })?.reference;
    const dedupeKey = reference ? `webhook:paystack:${body.event}:${reference}` : undefined;

    if (dedupeKey && (await this.redis.wasAlreadyProcessed(dedupeKey))) {
      this.logger.debug(`Skipping already-processed webhook delivery: ${dedupeKey}`);
      return { duplicate: true };
    }

    switch (body.event) {
      case 'charge.success':
        await this.handleChargeSuccess(body as PaystackChargeSuccessEvent);
        break;
      case 'transfer.success':
      case 'transfer.failed':
        await this.handleTransferEvent(body as PaystackTransferEvent);
        break;
      default:
        this.logger.debug(`Ignoring unhandled Paystack event type: ${body.event}`);
    }

    if (dedupeKey) await this.redis.markProcessed(dedupeKey);
    return { duplicate: false };
  }

  /**
   * Routes on metadata.purpose (set at /wallet/fund/initialize time) rather
   * than assuming every charge.success is a wallet top-up, so this same
   * webhook endpoint can grow other charge-backed flows later without
   * cross-crediting wallets.
   */
  private async handleChargeSuccess(event: PaystackChargeSuccessEvent): Promise<void> {
    const { reference, amount, metadata } = event.data;

    if (metadata?.purpose !== 'wallet_topup') {
      this.logger.debug(`Ignoring charge.success ${reference}: metadata.purpose is not wallet_topup`);
      return;
    }

    await this.applyVerifiedChargeSuccess(reference, amount);
  }

  /**
   * Credits the wallet for a charge already confirmed successful — by a
   * webhook delivery, or by ReconciliationService's verify-transaction call.
   * Atomic pending -> success transition: a second/concurrent call for the
   * same reference has its updateMany match zero rows, so the balance
   * increment below never runs twice no matter how many callers race in.
   */
  async applyVerifiedChargeSuccess(reference: string, paystackAmount: number): Promise<void> {
    const walletTransaction = await this.prisma.walletTransaction.findUnique({ where: { reference } });
    if (!walletTransaction) {
      this.logger.warn(`charge.success for unknown wallet_transaction reference ${reference}`);
      return;
    }
    if (walletTransaction.amount !== paystackAmount) {
      this.logger.warn(
        `charge.success amount mismatch for ${reference}: ledger has ${walletTransaction.amount}, Paystack sent ${paystackAmount}`,
      );
    }

    await this.prisma.$transaction(async (tx) => {
      const transitioned = await tx.walletTransaction.updateMany({
        where: { reference, status: 'pending' },
        data: { status: 'success' },
      });
      if (transitioned.count === 0) return;

      await tx.wallet.update({
        where: { id: walletTransaction.walletId },
        data: { balance: { increment: walletTransaction.amount } },
      });
    });
  }

  // Reconciliation's counterpart to applyVerifiedChargeSuccess when Paystack
  // reports the charge as failed/abandoned rather than successful. Same
  // atomic-conditional-update idempotency: a no-op if already resolved.
  async markChargeFailed(reference: string): Promise<void> {
    await this.prisma.walletTransaction.updateMany({
      where: { reference, status: 'pending' },
      data: { status: 'failed' },
    });
  }

  private async handleTransferEvent(event: PaystackTransferEvent): Promise<void> {
    const { reference } = event.data;
    const legStatus = event.event === 'transfer.success' ? 'success' : 'failed';
    await this.applyVerifiedTransferResult(reference, legStatus);
  }

  // Shared by the transfer.success/transfer.failed webhook handler and
  // ReconciliationService's verify-transfer call. Atomic per-leg
  // pending -> success/failed transition, same idempotency guarantee as
  // applyVerifiedChargeSuccess.
  //
  // Task 32: a transfer reference now means one of two things — an escrow
  // payout leg (restaurant/runner earnings, checked first since that's the
  // original/more common case) or a wallet withdrawal
  // (WalletService.initiateWithdrawal). Same webhook event type either
  // way; this is the one place both get resolved from.
  async applyVerifiedTransferResult(reference: string, legStatus: TransferLegResult): Promise<void> {
    const escrow = await this.prisma.orderEscrow.findFirst({
      where: { OR: [{ restaurantTransferReference: reference }, { runnerTransferReference: reference }] },
    });

    if (escrow) {
      if (escrow.restaurantTransferReference === reference) {
        await this.prisma.orderEscrow.updateMany({
          where: { id: escrow.id, restaurantTransferStatus: 'pending' },
          data: { restaurantTransferStatus: legStatus },
        });
      } else if (escrow.runnerTransferReference === reference) {
        await this.prisma.orderEscrow.updateMany({
          where: { id: escrow.id, runnerTransferStatus: 'pending' },
          data: { runnerTransferStatus: legStatus },
        });
      }
      return;
    }

    const walletTransaction = await this.prisma.walletTransaction.findUnique({ where: { reference } });
    if (!walletTransaction) {
      this.logger.warn(`Transfer result for unknown reference ${reference}`);
      return;
    }
    await this.applyVerifiedWithdrawalResult(walletTransaction, legStatus);
  }

  // Withdrawal transfers are the only debit-type WalletTransaction ever
  // created `pending` (an escrow_hold debit is created `success`
  // immediately — see OrderEscrowService.hold) — the balance was already
  // taken off the wallet synchronously at withdrawal-request time
  // (WalletService.initiateWithdrawal), so a `success` result here just
  // marks the ledger row complete; `failed` must give the money back, or
  // it's gone even though Paystack never sent it anywhere. Same
  // conditional-transition idempotency as applyVerifiedChargeSuccess: a
  // second call for an already-resolved reference is a no-op.
  private async applyVerifiedWithdrawalResult(
    walletTransaction: WalletTransaction,
    legStatus: TransferLegResult,
  ): Promise<void> {
    await this.prisma.$transaction(async (tx) => {
      const transitioned = await tx.walletTransaction.updateMany({
        where: { id: walletTransaction.id, status: 'pending' },
        data: { status: legStatus },
      });
      if (transitioned.count === 0) return;

      if (legStatus === 'failed') {
        await tx.wallet.update({
          where: { id: walletTransaction.walletId },
          data: { balance: { increment: walletTransaction.amount } },
        });
      }
    });
  }
}
