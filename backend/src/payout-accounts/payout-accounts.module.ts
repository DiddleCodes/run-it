import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { PaystackModule } from '../paystack/paystack.module';
import { PayoutAccountsController } from './payout-accounts.controller';
import { PayoutAccountsService } from './payout-accounts.service';

@Module({
  imports: [PaystackModule, CommonModule],
  controllers: [PayoutAccountsController],
  providers: [PayoutAccountsService],
  exports: [PayoutAccountsService],
})
export class PayoutAccountsModule {}
