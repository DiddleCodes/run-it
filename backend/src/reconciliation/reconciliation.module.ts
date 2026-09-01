import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { PaystackModule } from '../paystack/paystack.module';
import { WebhooksModule } from '../webhooks/webhooks.module';
import { ReconciliationController } from './reconciliation.controller';
import { ReconciliationService } from './reconciliation.service';

@Module({
  imports: [PaystackModule, WebhooksModule, CommonModule],
  controllers: [ReconciliationController],
  providers: [ReconciliationService],
  exports: [ReconciliationService],
})
export class ReconciliationModule {}
