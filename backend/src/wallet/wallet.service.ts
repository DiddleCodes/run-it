import { Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { FundWalletDto } from './dto/fund-wallet.dto';

@Injectable()
export class WalletService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
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
