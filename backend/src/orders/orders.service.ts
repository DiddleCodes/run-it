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
      data: { status: 'picked_up', handoffPhotoUrl, pickedUpAt: new Date() },
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

  async verifyDelivery(
    orderId: string,
    pin: string,
    amountCollectedKobo?: number,
  ): Promise<{ status: Order['status'] }> {
    const order = await this.getOrderOrThrow(orderId);

    // Idempotent: a retried correct submission after escrow already
    // released just confirms the state — it never calls release() again.
    // (release() is itself safe to call twice — see its own doc comment —
    // but there's no reason to touch Paystack at all once this is done.)
    if (order.status === 'delivered') return { status: order.status };
    if (order.status !== 'picked_up') {
      throw new ConflictException(`Order ${orderId} is ${order.status}, not yet picked up`);
    }

    // Task 47: bundled into this same call (not a separate "mark as paid"
    // endpoint a runner could simply never call) so a Pay on Delivery order
    // can never reach `delivered` without the platform recording what was
    // actually collected — checked before the PIN itself, since there's no
    // point burning a failed-attempt guess if this would reject anyway.
    if (order.paymentMethod === 'pay_on_delivery' && amountCollectedKobo === undefined) {
      throw new BadRequestException('Report the cash amount collected to confirm this delivery.');
    }

    await this.assertNotRateLimited(orderId, 'delivery');

    if (!codesMatch(pin, order.deliveryPin)) {
      await this.recordFailedAttempt(orderId, 'delivery');
      throw new BadRequestException("That PIN doesn't match this order.");
    }

    // This is now the ONLY path that reaches `delivered` — escrow.release()
    // flips order.status itself, atomically with the escrow status flip.
    // Unconditional regardless of payment method or (for POD) whatever cash
    // figure was reported below — the restaurant/runner are never made to
    // wait on a cash reconciliation that's a purely runner/platform matter
    // (see Order.paymentMethod's own doc comment).
    await this.escrow.release(orderId);
    await this.resetRateLimit(orderId, 'delivery');

    if (order.paymentMethod === 'pay_on_delivery' && amountCollectedKobo !== undefined) {
      await this.recordCashCollection(order, amountCollectedKobo);
    }

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
    const order = await this.prisma.order.findUnique({
      where: { id: orderId },
      include: { vendor: true, items: true },
    });
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
      // Task 46: the rest of a real order-history detail view — every
      // party already allowed to see this order at all can see its own
      // vendor/items/total/note and the full timestamped lifecycle.
      vendorName: order.vendor.businessName,
      totalAmount: order.totalAmount,
      deliveryLocationLabel: order.deliveryLocationLabel,
      note: order.note,
      items: order.items.map((item) => ({
        name: item.nameSnapshot,
        quantity: item.quantity,
        priceKobo: item.priceSnapshot,
      })),
      createdAt: order.createdAt,
      acceptedAt: order.acceptedAt,
      pickedUpAt: order.pickedUpAt,
      deliveredAt: order.deliveredAt,
      cancelledAt: order.cancelledAt,
    };
  }

  // Task 46: the student's own real order history — every order they've
  // ever placed (any status), most recent first. Deliberately no runner/
  // vendor equivalent here — out of this task's scope, and the vendor side
  // already has its own paginated list (VendorsService.listIncomingOrders).
  async getOrderHistoryForStudent(studentUserId: string, page: number, limit: number) {
    const where = { studentUserId };
    const [items, total] = await Promise.all([
      this.prisma.order.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { vendor: true, items: true },
      }),
      this.prisma.order.count({ where }),
    ]);

    return {
      items: items.map((order) => ({
        id: order.id,
        status: order.status,
        vendorName: order.vendor.businessName,
        totalAmount: order.totalAmount,
        note: order.note,
        deliveryLocationLabel: order.deliveryLocationLabel,
        items: order.items.map((item) => ({
          name: item.nameSnapshot,
          quantity: item.quantity,
          priceKobo: item.priceSnapshot,
        })),
        createdAt: order.createdAt,
        acceptedAt: order.acceptedAt,
        pickedUpAt: order.pickedUpAt,
        deliveredAt: order.deliveredAt,
        cancelledAt: order.cancelledAt,
      })),
      total,
      page,
      limit,
    };
  }

  // Task 47: called once, right after a Pay on Delivery order's escrow is
  // released (see verifyDelivery above) — records what the runner actually
  // collected as a debt owed to the platform (see CashCollectionDebt's own
  // schema doc comment). A mismatch against the order's real total opens a
  // real Dispute rather than silently recording a debt as if payment had
  // matched; `upsert` on both writes so a retried verify-delivery call
  // (idempotent per the early-return above once already `delivered`,
  // but this only ever runs on the one call that actually reached release)
  // can never violate either row's own one-per-order uniqueness.
  private async recordCashCollection(order: Order, amountCollectedKobo: number): Promise<void> {
    if (!order.runnerUserId) return;
    const mismatched = amountCollectedKobo !== order.totalAmount;

    await this.prisma.$transaction(async (tx) => {
      await tx.cashCollectionDebt.upsert({
        where: { orderId: order.id },
        create: {
          orderId: order.id,
          runnerId: order.runnerUserId!,
          amountOwed: order.totalAmount,
          amountCollected: amountCollectedKobo,
          status: mismatched ? 'disputed' : 'pending',
        },
        update: {},
      });

      if (mismatched) {
        await tx.dispute.upsert({
          where: { orderId: order.id },
          create: {
            orderId: order.id,
            reason: `Pay on Delivery cash mismatch — runner reported collecting ${amountCollectedKobo} kobo, order total was ${order.totalAmount} kobo`,
          },
          update: {},
        });
      }
    });
  }

  // Task 47: what a runner currently owes the platform from completed Pay
  // on Delivery deliveries — the running total the runner-facing Wallet
  // screen surfaces, plus enough detail to explain it. Only pending/disputed
  // rows count toward the total; a settled one is done, by definition.
  async getMyCashDebtSummary(runnerUserId: string) {
    const debts = await this.prisma.cashCollectionDebt.findMany({
      where: { runnerId: runnerUserId, status: { in: ['pending', 'disputed'] } },
      orderBy: { createdAt: 'desc' },
    });
    return {
      totalOwedKobo: debts.reduce((sum, debt) => sum + debt.amountOwed, 0),
      debts: debts.map((debt) => ({
        orderId: debt.orderId,
        amountOwed: debt.amountOwed,
        amountCollected: debt.amountCollected,
        status: debt.status,
        createdAt: debt.createdAt,
      })),
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
