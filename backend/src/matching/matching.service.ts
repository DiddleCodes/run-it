import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus } from '@prisma/client';
import { Queue } from 'bullmq';
import { PrismaService } from '../prisma/prisma.service';
import { ESCALATE_JOB, REBROADCAST_JOB, escalateJobId, rebroadcastJobId, MATCHING_QUEUE } from './matching.constants';
import { RunnerDispatchGateway } from './runner-dispatch.gateway';

// A rebroadcast/escalation only ever makes sense while the order is still
// genuinely waiting on a runner — matches VendorsService's own
// ACTIVE_ORDER_STATUSES convention, narrowed to the two statuses a runner
// can still be claimed into (see OrderEscrowService.claim's CLAIMABLE_STATUSES).
const STILL_WAITING_STATUSES: OrderStatus[] = ['preparing', 'ready_for_pickup'];

const JOB_OPTIONS = {
  attempts: 3,
  backoff: { type: 'exponential' as const, delay: 3_000 },
  removeOnComplete: { count: 1000 },
  removeOnFail: { count: 5000 },
};

/**
 * Task 21a: orchestrates the broadcast-and-claim runner-matching flow —
 * fires the initial new-job broadcast, schedules the short-window
 * re-broadcast and long-window admin/restaurant escalation as delayed
 * BullMQ jobs (the same queue-based deferred-work mechanism already used
 * for FCM pushes and webhook processing — no new scheduling primitive),
 * and cancels both once a claim succeeds.
 *
 * Deliberately reads Order fresh from Prisma at every check rather than
 * trusting stale job data — an order can move out of the "waiting on a
 * runner" state (claimed, cancelled) at any point between when a job is
 * scheduled and when it fires.
 */
@Injectable()
export class MatchingService {
  private readonly logger = new Logger(MatchingService.name);

  constructor(
    @InjectQueue(MATCHING_QUEUE) private readonly queue: Queue,
    private readonly gateway: RunnerDispatchGateway,
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  /**
   * Called once, at the moment an order first needs a runner (the
   * restaurant's "preparing" acceptance — see VendorsService.advanceOrderStatus).
   * Fires the initial broadcast and arms both timers.
   */
  async broadcastNewJob(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) {
      this.logger.warn(`broadcastNewJob called for unknown order ${orderId}`);
      return;
    }

    this.emit(order.id, order.vendorId);

    const rebroadcastSeconds = this.config.get<number>('matching.rebroadcastSeconds') as number;
    const escalateSeconds = this.config.get<number>('matching.escalateSeconds') as number;

    await Promise.all([
      this.queue.add(
        REBROADCAST_JOB,
        { orderId },
        { ...JOB_OPTIONS, jobId: rebroadcastJobId(orderId), delay: rebroadcastSeconds * 1000 },
      ),
      this.queue.add(
        ESCALATE_JOB,
        { orderId },
        { ...JOB_OPTIONS, jobId: escalateJobId(orderId), delay: escalateSeconds * 1000 },
      ),
    ]);
  }

  /** Delayed-job handler: re-broadcasts only if still genuinely unclaimed. */
  async handleRebroadcast(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order || order.runnerUserId || !STILL_WAITING_STATUSES.includes(order.status)) {
      return;
    }
    this.emit(order.id, order.vendorId);
  }

  /** Delayed-job handler: escalates to a Dispute only if still genuinely unclaimed. */
  async handleEscalate(orderId: string): Promise<void> {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order || order.runnerUserId || !STILL_WAITING_STATUSES.includes(order.status)) {
      return;
    }

    // upsert, not create: matches the delivery-proof-review Dispute's own
    // convention (Dispute.orderId is @unique) — a retried/duplicate
    // escalation job for the same order must not throw.
    await this.prisma.dispute.upsert({
      where: { orderId },
      create: { orderId, reason: 'No runner claimed this order within the matching window' },
      update: {},
    });
    this.logger.warn(`Order ${orderId} escalated — unclaimed past the matching window`);
  }

  /** Called on a successful claim — the order no longer needs either timer. */
  async cancelPendingJobs(orderId: string): Promise<void> {
    await Promise.all([
      this.queue.remove(rebroadcastJobId(orderId)).catch(() => undefined),
      this.queue.remove(escalateJobId(orderId)).catch(() => undefined),
    ]);
  }

  private emit(orderId: string, vendorId: string): void {
    this.gateway.broadcastNewJob({ orderId, vendorId });
  }
}
