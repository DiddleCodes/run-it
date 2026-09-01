import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { SelfOrAdminGuard } from '../common/guards/self-or-admin.guard';
import { CreatePayoutAccountDto } from './dto/create-payout-account.dto';
import { PayoutAccountsService } from './payout-accounts.service';

@Controller('payout-accounts')
export class PayoutAccountsController {
  constructor(private readonly payoutAccounts: PayoutAccountsService) {}

  // Reference data, not tied to any one user_id — declared ahead of
  // `:userId` below so Nest doesn't match "banks" as a userId param first.
  @Get('banks')
  @UseGuards(JwtAuthGuard)
  listBanks() {
    return this.payoutAccounts.listBanks();
  }

  @Post()
  @UseGuards(JwtAuthGuard, SelfOrAdminGuard)
  create(@Body() dto: CreatePayoutAccountDto) {
    return this.payoutAccounts.create(dto);
  }

  @Get(':userId')
  @UseGuards(JwtAuthGuard, SelfOrAdminGuard)
  findOne(@Param('userId') userId: string) {
    return this.payoutAccounts.findByUserId(userId);
  }
}
