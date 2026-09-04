import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { SelfOrAdminGuard } from '../common/guards/self-or-admin.guard';
import { FundWalletDto } from './dto/fund-wallet.dto';
import { WithdrawWalletDto } from './dto/withdraw-wallet.dto';
import { WalletService } from './wallet.service';

@Controller()
@UseGuards(JwtAuthGuard, SelfOrAdminGuard)
export class WalletController {
  constructor(private readonly wallet: WalletService) {}

  @Post('wallet/fund/initialize')
  initializeFunding(@Body() dto: FundWalletDto) {
    return this.wallet.initializeFunding(dto);
  }

  @Post('wallet/withdraw/initiate')
  initiateWithdrawal(@Body() dto: WithdrawWalletDto) {
    return this.wallet.initiateWithdrawal(dto);
  }

  @Get('wallet/:userId/balance')
  getBalance(@Param('userId') userId: string) {
    return this.wallet.getBalance(userId);
  }

  @Get('wallet/:userId/transactions')
  getTransactions(@Param('userId') userId: string, @Query('take') take?: string, @Query('skip') skip?: string) {
    return this.wallet.getTransactions(userId, take ? parseInt(take, 10) : undefined, skip ? parseInt(skip, 10) : undefined);
  }
}
