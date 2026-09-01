import { OnWorkerEvent, Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { AlertsService } from '../alerts/alerts.service';
import { PrismaService } from '../prisma/prisma.service';
import { FCM_PUSH_QUEUE } from './notifications.constants';
import { FcmService, PushPayload } from './fcm.service';

export interface FcmPushJob {
  userId: string;
  payload: PushPayload;
}

// "Registration token is not registered" — Firebase's own signal that a
// token is permanently dead (app uninstalled, token rotated). Pruning it
// here is what keeps DeviceToken from accumulating stale rows forever;
// every other failure is left to throw so BullMQ's attempts/backoff (same
// shape as WebhooksProcessor) retries it instead.
const UNREGISTERED_ERROR_CODE = 'messaging/registration-token-not-registered';

@Processor(FCM_PUSH_QUEUE)
export class FcmProcessor extends WorkerHost {
  private readonly logger = new Logger(FcmProcessor.name);

  constructor(
    private readonly fcm: FcmService,
    private readonly prisma: PrismaService,
    private readonly alerts: AlertsService,
  ) {
    super();
  }

  async process(job: Job<FcmPushJob>): Promise<void> {
    const { userId, payload } = job.data;
    const tokens = await this.prisma.deviceToken.findMany({ where: { userId } });

    if (tokens.length === 0) {
      this.logger.debug(`No device tokens registered for user ${userId} — nothing to push.`);
      return;
    }

    const failures: Error[] = [];
    for (const { token } of tokens) {
      try {
        await this.fcm.send(token, payload);
      } catch (err) {
        const code = (err as { code?: string }).code;
        if (code === UNREGISTERED_ERROR_CODE) {
          await this.prisma.deviceToken.delete({ where: { token } }).catch(() => undefined);
          this.logger.log(`Pruned dead device token for user ${userId}`);
          continue;
        }
        failures.push(err as Error);
      }
    }

    if (failures.length > 0) {
      throw new Error(`${failures.length}/${tokens.length} push send(s) failed: ${failures[0].message}`);
    }
  }

  @OnWorkerEvent('failed')
  async onFailed(job: Job<FcmPushJob> | undefined, error: Error): Promise<void> {
    if (!job) return;
    this.logger.error(`FCM push job ${job.id} (user ${job.data?.userId}) failed on attempt ${job.attemptsMade}: ${error.message}`);

    const maxAttempts = job.opts.attempts ?? 1;
    if (job.attemptsMade < maxAttempts) return;

    await this.alerts.send(`Push notification permanently failed after ${maxAttempts} attempts`, {
      jobId: job.id,
      userId: job.data?.userId,
      title: job.data?.payload?.title,
      error: error.message,
    });
  }
}
