import { InjectQueue } from '@nestjs/bullmq';
import { Controller, Headers, HttpCode, Post, RawBodyRequest, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { Queue } from 'bullmq';
import { Request } from 'express';
import { PaystackService } from '../paystack/paystack.service';
import { PaystackWebhookEvent } from '../paystack/paystack.types';
import { PaystackWebhookIpGuard } from './paystack-webhook-ip.guard';
import { PAYSTACK_WEBHOOK_QUEUE } from './webhooks.constants';

@Controller('webhooks')
export class WebhooksController {
  constructor(
    private readonly paystack: PaystackService,
    @InjectQueue(PAYSTACK_WEBHOOK_QUEUE) private readonly queue: Queue<PaystackWebhookEvent>,
  ) {}

  // Verifies the source IP and HMAC signature synchronously — both are
  // cheap, in-memory checks — then enqueues the event and returns
  // immediately. The actual DB work (crediting wallets, updating transfer
  // statuses) happens in WebhooksProcessor, off the request/response cycle,
  // so a slow or temporarily-broken worker can never make this endpoint
  // time out or trigger a Paystack retry storm.
  @Post('paystack')
  @UseGuards(PaystackWebhookIpGuard, ThrottlerGuard)
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @HttpCode(200)
  async handlePaystack(
    @Req() req: RawBodyRequest<Request>,
    @Headers('x-paystack-signature') signature?: string,
  ): Promise<{ received: boolean; queued: boolean }> {
    if (!this.paystack.verifyWebhookSignature(req.rawBody as Buffer, signature)) {
      throw new UnauthorizedException('Invalid Paystack signature');
    }

    const body = req.body as PaystackWebhookEvent;
    await this.queue.add('paystack-event', body, {
      attempts: 5,
      backoff: { type: 'exponential', delay: 5_000 },
      removeOnComplete: { count: 1000 },
      removeOnFail: { count: 5000 },
    });

    return { received: true, queued: true };
  }
}
