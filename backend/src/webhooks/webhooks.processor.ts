import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { AlertsService } from '../alerts/alerts.service';
import { PaystackWebhookEvent } from '../paystack/paystack.types';
import { WebhooksService } from './webhooks.service';
import { PAYSTACK_WEBHOOK_QUEUE } from './webhooks.constants';

@Processor(PAYSTACK_WEBHOOK_QUEUE)
export class WebhooksProcessor extends WorkerHost {
  private readonly logger = new Logger(WebhooksProcessor.name);

  constructor(
    private readonly webhooks: WebhooksService,
    private readonly alerts: AlertsService,
  ) {
    super();
  }

  // Left to throw on failure (not caught here) — that's what tells BullMQ
  // to retry the job per the attempts/backoff configured when it was
  // enqueued. applyPaystackEvent is safe to re-run: see its own doc comment.
  async process(job: Job<PaystackWebhookEvent>): Promise<void> {
    await this.webhooks.applyPaystackEvent(job.data);
  }

  @OnWorkerEvent('failed')
  async onFailed(job: Job<PaystackWebhookEvent> | undefined, error: Error): Promise<void> {
    if (!job) return;
    this.logger.error(
      `Webhook job ${job.id} (${job.data?.event}) failed on attempt ${job.attemptsMade}: ${error.message}`,
    );

    const maxAttempts = job.opts.attempts ?? 1;
    if (job.attemptsMade < maxAttempts) return; // still has retries left — not alert-worthy yet

    await this.alerts.send(`Webhook processing permanently failed after ${maxAttempts} attempts`, {
      jobId: job.id,
      event: job.data?.event,
      error: error.message,
      data: job.data,
    });
  }
}
