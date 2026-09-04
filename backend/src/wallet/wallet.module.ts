import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { PaystackModule } from '../paystack/paystack.module';
import { WebhooksModule } from '../webhooks/webhooks.module';
import { WalletController } from './wallet.controller';
import { WalletService } from './wallet.service';

@Module({
  imports: [PaystackModule, CommonModule, WebhooksModule],
  controllers: [WalletController],
  providers: [WalletService],
  exports: [WalletService],
})
export class WalletModule {}
