import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { PaystackModule } from '../paystack/paystack.module';
import { PaystackWebhookIpGuard } from './paystack-webhook-ip.guard';
import { PAYSTACK_WEBHOOK_QUEUE } from './webhooks.constants';
import { WebhooksController } from './webhooks.controller';
import { WebhooksProcessor } from './webhooks.processor';
import { WebhooksService } from './webhooks.service';

@Module({
  imports: [PaystackModule, BullModule.registerQueue({ name: PAYSTACK_WEBHOOK_QUEUE })],
  controllers: [WebhooksController],
  providers: [WebhooksService, WebhooksProcessor, PaystackWebhookIpGuard],
  exports: [WebhooksService],
})
export class WebhooksModule {}
