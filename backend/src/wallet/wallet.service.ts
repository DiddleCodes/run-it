import { BadGatewayException, HttpException, HttpStatus, Injectable, NotFoundException, UnprocessableEntityException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { AlertsService } from '../alerts/alerts.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { WebhooksService } from '../webhooks/webhooks.service';
import { FundWalletDto } from './dto/fund-wallet.dto';
import { WithdrawWalletDto } from './dto/withdraw-wallet.dto';

@Injectable()
export class WalletService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly webhooks: WebhooksService,
    private readonly alerts: AlertsService,
  ) {}

  private async getWalletForUser(userId: string) {
    const wallet = await this.prisma.wallet.findUnique({ where: { userId } });
    if (!wallet) throw new NotFoundException('No wallet for this user');
    return wallet;
  }

  async initializeFunding(dto: FundWalletDto) {
    const wallet = await this.getWalletForUser(dto.userId);
    const reference = `wallet_fund_${randomUUID()}`;

    // Row created up front, status=pending. The webhook flips it to
    // success/failed exactly once — this is what makes charge.success
    // idempotent regardless of how many times Paystack redelivers it.
    const walletTransaction = await this.prisma.walletTransaction.create({
      data: {
        walletId: wallet.id,
        type: 'credit',
        amount: dto.amountKobo,
        reference,
        status: 'pending',
        metadata: { purpose: 'wallet_topup', userId: dto.userId },
      },
    });

    try {
      const paystackData = await this.paystack.initializeTransaction({
        email: dto.email,
        amountKobo: dto.amountKobo,
        reference,
        metadata: {
          purpose: 'wallet_topup',
          userId: dto.userId,
          walletTransactionId: walletTransaction.id,
        },
      });

      return {
        reference,
        authorizationUrl: paystackData.authorization_url,
        accessCode: paystackData.access_code,
      };
    } catch (err) {
      // Paystack never got a reference to redeliver charge.success for, so
      // this ledger row would otherwise sit pending forever.
      await this.prisma.walletTransaction.update({
        where: { id: walletTransaction.id },
        data: { status: 'failed' },
      });
      throw err;
    }
  }

  /**
   * Task 32: real withdrawal to the user's own confirmed bank account
   * (PayoutAccountsService — reused unchanged, just no longer restricted to
   * restaurant/runner accounts). Two-phase, mirroring the safe-failure
   * shape OrderEscrowService.release() proved for escrow payouts (Task 31):
   *
   *   1. Debit the wallet *first*, atomically — the same conditional
   *      `updateMany` gte-check OrderEscrowService.hold() uses, so two
   *      concurrent withdrawals of the same balance can't both succeed.
   *      The ledger row is created `pending`, not `success`: unlike an
   *      escrow_hold debit (money just moving to an internal ledger), this
   *      debit isn't really final until Paystack actually sends it
   *      somewhere.
   *   2. Only then call Paystack. If that call itself throws (rejected
   *      synchronously), the debit above already committed — reversed
   *      right here via the exact same idempotent path a delayed
   *      transfer.failed webhook uses (WebhooksService.
   *      applyVerifiedTransferResult), so there's exactly one reversal
   *      code path, not two that could drift apart. If Paystack accepts it
   *      (a real transfer initiated, status `pending` on their side), the
   *      ledger row stays `pending` until the transfer.success/failed
   *      webhook — or ReconciliationService, if that webhook is lost —
   *      resolves it through that same shared path.
   */
  async initiateWithdrawal(dto: WithdrawWalletDto) {
    const wallet = await this.getWalletForUser(dto.userId);
    const payoutAccount = await this.prisma.payoutAccount.findUnique({ where: { userId: dto.userId } });
    if (!payoutAccount) {
      throw new UnprocessableEntityException('Add a bank account before withdrawing');
    }

    const reference = `wallet_withdraw_${randomUUID()}`;

    const walletTransaction = await this.prisma.$transaction(async (tx) => {
      // Conditional decrement: only succeeds if the balance still covers
      // the withdrawal at the moment of the write — same guarantee
      // OrderEscrowService.hold() uses for order payments, applied here to
      // a withdrawal instead.
      const debited = await tx.wallet.updateMany({
        where: { id: wallet.id, balance: { gte: dto.amountKobo } },
        data: { balance: { decrement: dto.amountKobo } },
      });
      if (debited.count === 0) {
        throw new HttpException('Insufficient wallet balance', HttpStatus.PAYMENT_REQUIRED);
      }

      return tx.walletTransaction.create({
        data: {
          walletId: wallet.id,
          type: 'debit',
          amount: dto.amountKobo,
          reference,
          status: 'pending',
          metadata: { purpose: 'wallet_withdrawal', userId: dto.userId, payoutAccountId: payoutAccount.id },
        },
      });
    });

    try {
      await this.paystack.initiateTransfer({
        amountKobo: dto.amountKobo,
        recipientCode: payoutAccount.paystackRecipientCode,
        reference,
        reason: 'RUN-It wallet withdrawal',
      });
    } catch (err) {
      // The root Paystack error was already captured to Sentry inside
      // PaystackService.request() (Task 31) — this is the "real user
      // money" alert Task 31 established for OrderEscrowService.release()'s
      // own transfer failures, same severity class.
      await this.webhooks.applyVerifiedTransferResult(reference, 'failed');
      await this.alerts.send(`Wallet withdrawal failed to initiate for user ${dto.userId}`, {
        userId: dto.userId,
        reference,
        amountKobo: dto.amountKobo,
        error: (err as Error).message,
      });
      throw new BadGatewayException('Withdrawal could not be initiated — your balance has not been affected');
    }

    return walletTransaction;
  }

  async getBalance(userId: string) {
    const wallet = await this.getWalletForUser(userId);
    return { userId, balanceKobo: wallet.balance };
  }

  async getTransactions(userId: string, take = 50, skip = 0) {
    const wallet = await this.getWalletForUser(userId);
    return this.prisma.walletTransaction.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: 'desc' },
      take,
      skip,
    });
  }
}
