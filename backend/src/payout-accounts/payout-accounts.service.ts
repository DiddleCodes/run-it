import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { CreatePayoutAccountDto } from './dto/create-payout-account.dto';

@Injectable()
export class PayoutAccountsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
  ) {}

  async create(dto: CreatePayoutAccountDto) {
    const user = await this.prisma.user.findUnique({ where: { id: dto.userId } });
    if (!user) throw new NotFoundException('User not found');
    if (user.accountType !== 'restaurant' && user.accountType !== 'runner') {
      throw new BadRequestException('Only restaurant and runner accounts can register payout details');
    }

    // Throws UnprocessableEntityException if Paystack can't verify the pair.
    const resolved = await this.paystack.resolveAccount({
      accountNumber: dto.accountNumber,
      bankCode: dto.bankCode,
    });

    const recipient = await this.paystack.createTransferRecipient({
      accountName: resolved.accountName,
      accountNumber: resolved.accountNumber,
      bankCode: dto.bankCode,
    });

    return this.prisma.payoutAccount.upsert({
      where: { userId: dto.userId },
      create: {
        userId: dto.userId,
        bankCode: dto.bankCode,
        accountNumber: resolved.accountNumber,
        accountName: resolved.accountName,
        paystackRecipientCode: recipient.recipientCode,
      },
      update: {
        bankCode: dto.bankCode,
        accountNumber: resolved.accountNumber,
        accountName: resolved.accountName,
        paystackRecipientCode: recipient.recipientCode,
      },
    });
  }

  async findByUserId(userId: string) {
    const account = await this.prisma.payoutAccount.findUnique({ where: { userId } });
    if (!account) throw new NotFoundException('No payout account on file for this user');
    return account;
  }

  listBanks() {
    return this.paystack.listBanks();
  }
}
