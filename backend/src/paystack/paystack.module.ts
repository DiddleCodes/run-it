import { Module } from '@nestjs/common';
import { PaymentCallbackController } from './payment-callback.controller';
import { PaystackService } from './paystack.service';

@Module({
  controllers: [PaymentCallbackController],
  providers: [PaystackService],
  exports: [PaystackService],
})
export class PaystackModule {}
