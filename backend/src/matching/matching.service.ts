import { InjectQueue } from '@nestjs/bullmq';
import { ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderStatus } from '@prisma/client';
import { Queue } from 'bullmq';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { PrismaService } from '../prisma/prisma.service';
import { ESCALATE_JOB, REBROADCAST_JOB, escalateJobId, rebroadcastJobId, MATCHING_QUEUE } from './matching.constants';
import { RunnerDispatchGateway } from './runner-dispatch.gateway';

export interface AvailableJob {
  orderId: string;
  vendorId: string;
  vendorName: string;
  deliveryLocationLabel: string | null;
  payoutAmount: number;
  totalAmount: number;
  // Task 47: lets the runner see, before accepting, that this delivery
  // needs cash collected from the student rather than nothing further to
  // do at drop-off — surfaced as a badge on the job card.
  isPayOnDelivery: boolean;
  createdAt: Date;
}

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
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { vendor: { select: { user: { select: { campusId: true } } } } },
    });
    if (!order) {
      this.logger.warn(`broadcastNewJob called for unknown order ${orderId}`);
      return;
    }

    this.emit(order.id, order.vendorId, order.vendor.user.campusId);

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
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { vendor: { select: { user: { select: { campusId: true } } } } },
    });
    if (!order || order.runnerUserId || !STILL_WAITING_STATUSES.includes(order.status)) {
      return;
    }
    this.emit(order.id, order.vendorId, order.vendor.user.campusId);
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

  /**
   * Task 21b: the broadcast/rebroadcast alone can't back a "what's
   * available right now" screen — rebroadcast is a one-shot delayed job
   * (fires once, `rebroadcastSeconds` after the order first went out), not
   * a recurring heartbeat, so a runner who wasn't connected to the socket
   * during that window would otherwise never see the order at all, on any
   * later reconnect. Reads the same STILL_WAITING_STATUSES/runnerUserId
   * criteria the broadcast/rebroadcast checks already use.
   */
  async listAvailable(runner: JwtPayload): Promise<AvailableJob[]> {
    if (runner.accountType !== 'runner') {
      throw new ForbiddenException('Only runner accounts can browse available orders');
    }

    // Task 26: no assigned campus yet (an admin hasn't onboarded this
    // runner) means genuinely nothing to show — same "null campus ->
    // empty, not unscoped" default as VendorsService.listVendors, not an
    // error, since a freshly-created runner account hitting this before
    // admin assignment is an expected, non-broken state.
    if (!runner.campusId) return [];

    const orders = await this.prisma.order.findMany({
      where: {
        runnerUserId: null,
        status: { in: STILL_WAITING_STATUSES },
        vendor: { user: { campusId: runner.campusId } },
      },
      include: { vendor: true, escrow: true },
      orderBy: { createdAt: 'asc' },
    });

    return orders
      .filter((order) => order.escrow != null)
      .map((order) => ({
        orderId: order.id,
        vendorId: order.vendorId,
        vendorName: order.vendor.businessName,
        deliveryLocationLabel: order.deliveryLocationLabel,
        payoutAmount: order.escrow!.runnerShare,
        totalAmount: order.totalAmount,
        isPayOnDelivery: order.paymentMethod === 'pay_on_delivery',
        createdAt: order.createdAt,
      }));
  }

  /** Called on a successful claim — the order no longer needs either timer. */
  async cancelPendingJobs(orderId: string): Promise<void> {
    await Promise.all([
      this.queue.remove(rebroadcastJobId(orderId)).catch(() => undefined),
      this.queue.remove(escalateJobId(orderId)).catch(() => undefined),
    ]);
  }

  // Task 26: an order's campus is its vendor's campus — a student can only
  // ever have placed this order with a same-campus restaurant in the first
  // place (VendorsService.listVendors' own scoping guarantees that), so
  // there's no separate campus concept needed on Order itself. A vendor
  // with no campusId (not yet admin-assigned) broadcasts to nobody rather
  // than falling back to some shared/unscoped room — see
  // RunnerDispatchGateway.broadcastNewJob.
  private emit(orderId: string, vendorId: string, campusId: string | null): void {
    this.gateway.broadcastNewJob({ orderId, vendorId, campusId });
  }
}
