import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Dispute, Order } from '@prisma/client';
import { timingSafeEqual } from 'crypto';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { NotificationsEmitterService } from '../notifications/notifications-emitter.service';
import { OrderEscrowService } from '../order-escrow/order-escrow.service';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { DeliveryProofDto } from './dto/delivery-proof.dto';
import { ReportProblemDto } from './dto/report-problem.dto';

type VerificationKind = 'pickup' | 'delivery';

// Counts only *failed* attempts (see recordFailedAttempt) — a runner
// retrying a downstream failure (e.g. Paystack transfer initiation) with
// the still-correct PIN never burns this budget, only repeated wrong
// guesses do.
const MAX_FAILED_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_SECONDS = 15 * 60;

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly escrow: OrderEscrowService,
    private readonly redis: RedisService,
    private readonly notifications: NotificationsEmitterService,
  ) {}

  // Task 30: `handoffPhotoUrl` is required (VerifyPickupDto rejects a
  // request with none before this ever runs) — the restaurant-to-runner
  // handoff's own chain-of-custody photo, captured by the runner at the
  // same moment they scan the vendor-shown pickup code. See
  // Order.handoffPhotoUrl's schema doc comment for why this is a hard
  // block rather than a soft warning.
  async verifyPickup(orderId: string, code: string, handoffPhotoUrl: string): Promise<{ status: Order['status'] }> {
    const order = await this.getOrderOrThrow(orderId);

    // Idempotent: a retried correct scan after pickup already succeeded
    // just confirms the current state rather than re-validating anything.
    // Task 12: gated on `ready_for_pickup` (the vendor's own "Mark Ready
    // for Pickup" action), not `placed` — a runner can't verify pickup
    // before the kitchen actually says the food is ready.
    if (order.status !== 'ready_for_pickup') {
      if (order.status === 'picked_up' || order.status === 'delivered') return { status: order.status };
      throw new ConflictException(`Order ${orderId} is ${order.status}, not awaiting pickup`);
    }

    await this.assertNotRateLimited(orderId, 'pickup');

    if (!codesMatch(code, order.pickupCode)) {
      await this.recordFailedAttempt(orderId, 'pickup');
      throw new BadRequestException("This isn't the order you accepted.");
    }

    const updated = await this.prisma.order.update({
      where: { id: orderId },
      data: { status: 'picked_up', handoffPhotoUrl },
    });
    await this.resetRateLimit(orderId, 'pickup');

    this.notifications.emit({
      type: 'order_picked_up',
      recipientUserId: order.studentUserId,
      title: 'Order picked up',
      body: 'Your order has been picked up and is on its way.',
      data: { orderId },
    });

    return { status: updated.status };
  }

  async verifyDelivery(orderId: string, pin: string): Promise<{ status: Order['status'] }> {
    const order = await this.getOrderOrThrow(orderId);

    // Idempotent: a retried correct submission after escrow already
    // released just confirms the state — it never calls release() again.
    // (release() is itself safe to call twice — see its own doc comment —
    // but there's no reason to touch Paystack at all once this is done.)
    if (order.status === 'delivered') return { status: order.status };
    if (order.status !== 'picked_up') {
      throw new ConflictException(`Order ${orderId} is ${order.status}, not yet picked up`);
    }

    await this.assertNotRateLimited(orderId, 'delivery');

    if (!codesMatch(pin, order.deliveryPin)) {
      await this.recordFailedAttempt(orderId, 'delivery');
      throw new BadRequestException("That PIN doesn't match this order.");
    }

    // This is now the ONLY path that reaches `delivered` — escrow.release()
    // flips order.status itself, atomically with the escrow status flip.
    await this.escrow.release(orderId);
    await this.resetRateLimit(orderId, 'delivery');

    this.notifications.emit({
      type: 'order_delivered',
      recipientUserId: order.studentUserId,
      title: 'Order delivered',
      body: 'Your order has been delivered. Enjoy!',
      data: { orderId },
    });

    return { status: 'delivered' };
  }

  async submitDeliveryProof(orderId: string, dto: DeliveryProofDto): Promise<Order> {
    const order = await this.getOrderOrThrow(orderId);
    if (order.status !== 'picked_up') {
      throw new ConflictException(
        `Order ${orderId} is ${order.status}, not yet picked up — nothing to submit delivery proof for`,
      );
    }

    // Deliberately does NOT advance status to `delivered` — a photo is not
    // treated as equivalent to a verified delivery. It only flags the order
    // for a human to resolve, e.g. via the existing admin-authorized
    // POST /orders/:orderId/escrow/release once reviewed.
    //
    // Task 13c: also opens an admin-facing Dispute in the same transaction —
    // this used to be a dead end with no resolution path at all. `upsert`
    // (not `create`) because a resubmitted proof on the same still-
    // `picked_up` order must not violate Dispute.orderId's uniqueness.
    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.order.update({
        where: { id: orderId },
        data: {
          deliveryProofUrl: dto.photoUrl,
          deliveryProofSubmittedAt: new Date(),
          needsManualReview: true,
        },
      });
      await tx.dispute.upsert({
        where: { orderId },
        create: { orderId, reason: 'Delivery proof submitted — PIN verification unavailable' },
        update: {},
      });
      return updated;
    });
  }

  // Task 30: the real student-facing "report a problem" entry point —
  // reuses the existing Dispute model exactly as the admin-only
  // AdminDisputesService.open() does, just scoped to the order's own
  // student rather than admin-gated. Same one-dispute-per-order
  // constraint (Dispute.orderId is @unique) and the same 409 an admin's
  // duplicate open() attempt gets — a student can't file two reports on
  // the same order, and a report never clobbers an already-open dispute
  // (e.g. a delivery-proof-fallback one) rather than silently overwriting
  // its reason.
  async reportProblem(orderId: string, studentUserId: string, dto: ReportProblemDto): Promise<Dispute> {
    const order = await this.getOrderOrThrow(orderId);
    if (order.studentUserId !== studentUserId) {
      throw new ForbiddenException('You are not the student on this order');
    }

    const existing = await this.prisma.dispute.findUnique({ where: { orderId } });
    if (existing) {
      throw new ConflictException(`A dispute already exists for order ${orderId}`);
    }

    return this.prisma.dispute.create({
      data: { orderId, reason: dto.reason, reporterPhotoUrl: dto.photoUrl },
    });
  }

  async getOrderForViewer(orderId: string, user: JwtPayload) {
    const order = await this.prisma.order.findUnique({ where: { id: orderId }, include: { vendor: true } });
    if (!order) throw new NotFoundException('Order not found');

    const isAdmin = user.role === 'admin' || user.role === 'internal_service';
    const isStudent = order.studentUserId === user.sub;
    const isRunner = order.runnerUserId === user.sub;
    const isVendorOwner = order.vendor.userId === user.sub;
    if (!isAdmin && !isStudent && !isRunner && !isVendorOwner) {
      throw new ForbiddenException('You are not a party to this order');
    }

    return {
      id: order.id,
      status: order.status,
      needsManualReview: order.needsManualReview,
      // Only the party who is meant to show/verify each code in person
      // ever sees it here — exposing pickupCode/deliveryPin to the runner
      // themself would let them bypass the physical handoff this whole
      // feature exists to enforce.
      pickupCode: isVendorOwner || isAdmin ? order.pickupCode : undefined,
      deliveryPin: isStudent || isAdmin ? order.deliveryPin : undefined,
    };
  }

  private async getOrderOrThrow(orderId: string): Promise<Order> {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    return order;
  }

  private async assertNotRateLimited(orderId: string, kind: VerificationKind): Promise<void> {
    const attempts = await this.redis.get(this.rateLimitKey(orderId, kind));
    if (attempts && Number(attempts) >= MAX_FAILED_ATTEMPTS) {
      throw new HttpException(
        'Too many incorrect attempts on this order — try again later.',
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private async recordFailedAttempt(orderId: string, kind: VerificationKind): Promise<void> {
    const key = this.rateLimitKey(orderId, kind);
    const attempts = await this.redis.incr(key);
    if (attempts === 1) await this.redis.expire(key, RATE_LIMIT_WINDOW_SECONDS);
  }

  private async resetRateLimit(orderId: string, kind: VerificationKind): Promise<void> {
    await this.redis.del(this.rateLimitKey(orderId, kind));
  }

  private rateLimitKey(orderId: string, kind: VerificationKind): string {
    return `verify_attempts:${kind}:${orderId}`;
  }
}

function codesMatch(submitted: string, expected: string): boolean {
  const a = Buffer.from(submitted, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
