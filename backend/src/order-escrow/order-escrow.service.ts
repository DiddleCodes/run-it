import {
  BadGatewayException,
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OrderEscrow, OrderStatus, Prisma } from '@prisma/client';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { MatchingService } from '../matching/matching.service';
import { NotificationsEmitterService } from '../notifications/notifications-emitter.service';
import { PaystackService } from '../paystack/paystack.service';
import { PrismaService } from '../prisma/prisma.service';
import { computeCommissionShares } from './commission.util';
import { HoldEscrowDto } from './dto/hold-escrow.dto';
import { generateVerificationCode } from '../orders/pin-code.util';

// Task 21a: an order can only be claimed while it's genuinely still
// waiting on a runner — before a restaurant accepts (`placed`) there's
// nothing to hand off yet, and after pickup/delivery/cancellation a claim
// no longer makes sense. Mirrors MatchingService's own
// STILL_WAITING_STATUSES.
const CLAIMABLE_STATUSES: OrderStatus[] = ['preparing', 'ready_for_pickup'];

@Injectable()
export class OrderEscrowService {
  private readonly logger = new Logger(OrderEscrowService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly paystack: PaystackService,
    private readonly config: ConfigService,
    private readonly notifications: NotificationsEmitterService,
    private readonly matching: MatchingService,
  ) {}

  async hold(orderId: string, dto: HoldEscrowDto): Promise<OrderEscrow> {
    const existing = await this.prisma.orderEscrow.findUnique({ where: { orderId } });
    if (existing) throw new ConflictException(`Escrow already exists for order ${orderId} (status: ${existing.status})`);

    const wallet = await this.prisma.wallet.findUnique({ where: { userId: dto.studentUserId } });
    if (!wallet) throw new NotFoundException('No wallet for this student');

    const foodSubtotalKobo = dto.grossAmountKobo;
    const deliveryFeeKobo =
      dto.deliveryFeeKobo ?? (this.config.get<number>('escrow.defaultDeliveryFeeKobo') as number);
    const totalAmountKobo = foodSubtotalKobo + deliveryFeeKobo;

    // Populated inside the transaction below, read after it commits — the
    // order_placed notification must never fire for a hold that ultimately
    // rolled back (insufficient balance, a concurrent duplicate, etc.).
    let vendorId!: string;

    const escrow = await this.prisma.$transaction(async (tx) => {
      // Conditional decrement: only succeeds if the balance still covers the
      // debit at the moment of the write, so concurrent holds on the same
      // wallet can't overdraw it.
      const debited = await tx.wallet.updateMany({
        where: { id: wallet.id, balance: { gte: totalAmountKobo } },
        data: { balance: { decrement: totalAmountKobo } },
      });
      if (debited.count === 0) {
        throw new HttpException('Insufficient wallet balance', HttpStatus.PAYMENT_REQUIRED);
      }

      const walletTransaction = await tx.walletTransaction.create({
        data: {
          walletId: wallet.id,
          type: 'debit',
          amount: totalAmountKobo,
          reference: `escrow_hold_${orderId}`,
          status: 'success',
          metadata: { orderId, purpose: 'escrow_hold' },
        },
      });

      const resolved = await this.resolveVendor(tx, dto.restaurantUserId, dto.vendorId);
      vendorId = resolved.vendorId;
      const { commissionRateOverride } = resolved;

      const { platformFee, restaurantShare, runnerShare } = computeCommissionShares(
        foodSubtotalKobo,
        deliveryFeeKobo,
        {
          restaurantCommissionRate:
            commissionRateOverride ?? (this.config.get<number>('escrow.restaurantCommissionRate') as number),
          runnerDeliveryFeeShare: this.config.get<number>('escrow.runnerDeliveryFeeShare') as number,
        },
      );

      // Task 9: this is the only place an Order row is ever created — see
      // Order's schema doc comment for why that's deliberate. Upsert rather
      // than create so a retried hold (blocked above once an escrow exists,
      // but not before that check on a genuinely fresh retry) can't crash
      // on a duplicate id.
      await tx.order.upsert({
        where: { id: orderId },
        create: {
          id: orderId,
          studentUserId: dto.studentUserId,
          vendorId,
          // Task 21a: nullable now — omitted entirely once the order needs
          // real runner-matching rather than a runner resolved up front.
          runnerUserId: dto.runnerUserId ?? null,
          status: 'placed',
          totalAmount: totalAmountKobo,
          deliveryLocationLabel: dto.deliveryLocationLabel,
          // Task 11: generated once, at creation, never regenerated on a
          // retried upsert (the `update: {}` below leaves them untouched).
          pickupCode: generateVerificationCode(),
          deliveryPin: generateVerificationCode(),
        },
        update: {},
      });

      if (dto.items?.length) {
        await tx.orderItem.createMany({
          data: dto.items.map((item) => ({
            orderId,
            menuItemId: item.menuItemId,
            nameSnapshot: item.name,
            priceSnapshot: item.priceKobo,
            quantity: item.quantity,
            notes: item.notes,
          })),
        });
      }

      try {
        return await tx.orderEscrow.create({
          data: {
            orderId,
            studentWalletTransactionId: walletTransaction.id,
            restaurantUserId: dto.restaurantUserId,
            runnerUserId: dto.runnerUserId ?? null,
            status: 'held',
            grossAmount: totalAmountKobo,
            platformFee,
            restaurantShare,
            runnerShare,
          },
        });
      } catch (err) {
        // The findUnique check above is best-effort, not a lock — two
        // concurrent hold() calls for the same orderId can both pass it and
        // both reach this create(). order_escrows.order_id's unique
        // constraint is what actually prevents the duplicate; this just
        // turns the loser's raw P2002 into the same clean 409 the
        // early-exit check gives everyone else, instead of a generic 500.
        if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') {
          throw new ConflictException(`Escrow already exists for order ${orderId}`);
        }
        throw err;
      }
    });

    this.notifications.emit({
      type: 'order_placed',
      recipientUserId: dto.restaurantUserId,
      title: 'New order received',
      body: `You have a new order (${orderId}) waiting to be accepted.`,
      data: { orderId, vendorId },
    });

    return escrow;
  }

  /**
   * Task 21a: an available runner claiming a broadcast, first-to-claim-wins.
   * The correctness requirement is entirely in the WHERE clause below, not
   * in any prior read — two concurrent calls for the same order both reach
   * this `updateMany`, but only the one whose UPDATE commits first still
   * finds `runner_user_id IS NULL` true; Postgres's row lock makes the
   * second call block until the first commits, then re-evaluate against
   * the now-non-null row and affect zero rows. Same conditional-update
   * shape this file already uses for the wallet debit in hold() and the
   * status flip in refund() — no new concurrency primitive.
   */
  async claim(orderId: string, runner: JwtPayload): Promise<OrderEscrow> {
    if (runner.accountType !== 'runner') {
      throw new ForbiddenException('Only runner accounts can claim orders');
    }

    const escrow = await this.findByOrderId(orderId);

    // Idempotent: the same runner's own retried claim (e.g. after a
    // network hiccup that hid a successful response) just confirms the
    // state rather than erroring.
    if (escrow.runnerUserId === runner.sub) {
      return escrow;
    }

    const order = await this.prisma.order.findUniqueOrThrow({ where: { id: orderId } });
    if (!CLAIMABLE_STATUSES.includes(order.status)) {
      throw new ConflictException(`Order ${orderId} is ${order.status} and cannot be claimed`);
    }

    const won = await this.prisma.$transaction(async (tx) => {
      const result = await tx.orderEscrow.updateMany({
        where: { orderId, runnerUserId: null },
        data: { runnerUserId: runner.sub },
      });
      if (result.count === 0) return false;

      // Kept in sync per Order.runnerUserId's own doc comment — scoped to
      // `runnerUserId: null` too, purely for defense in depth (the escrow
      // update above is what actually decided the race).
      await tx.order.updateMany({
        where: { id: orderId, runnerUserId: null },
        data: { runnerUserId: runner.sub },
      });
      return true;
    });

    if (!won) {
      throw new ConflictException({
        statusCode: HttpStatus.CONFLICT,
        code: 'ORDER_ALREADY_CLAIMED',
        message: 'This order has already been claimed by another runner',
      });
    }

    await this.matching.cancelPendingJobs(orderId);

    return this.findByOrderId(orderId);
  }

  async release(orderId: string): Promise<OrderEscrow> {
    let escrow = await this.findByOrderId(orderId);

    if (escrow.status === 'refunded') {
      throw new ConflictException(`Escrow for order ${orderId} was refunded and cannot be released`);
    }

    // Task 21a: runnerUserId is nullable at hold time now, but release()
    // can only ever be reached via EscrowPartyGuard's 'runner' check
    // (POST /orders/:orderId/escrow/release, or verify-delivery which
    // calls this internally) — both require the caller's JWT sub to equal
    // escrow.runnerUserId, which is impossible while it's still null. This
    // is therefore a defensive assertion (and a type-narrowing one for the
    // lookup below), not a reachable runtime path.
    if (!escrow.runnerUserId) {
      throw new UnprocessableEntityException(`Order ${orderId} has no runner attached — cannot release runner payout`);
    }

    const [restaurantPayout, runnerPayout] = await Promise.all([
      this.prisma.payoutAccount.findUnique({ where: { userId: escrow.restaurantUserId } }),
      this.prisma.payoutAccount.findUnique({ where: { userId: escrow.runnerUserId } }),
    ]);
    if (!restaurantPayout) throw new UnprocessableEntityException('Restaurant has no payout account on file');
    if (!runnerPayout) throw new UnprocessableEntityException('Runner has no payout account on file');

    // Each leg only transfers if it hasn't already been initiated, so a
    // retry after a partial failure never double-pays a leg that already
    // went out.
    let transferFailure: Error | undefined;

    if (!escrow.restaurantTransferReference) {
      try {
        const reference = `escrow_${escrow.id}_restaurant`;
        await this.paystack.initiateTransfer({
          amountKobo: escrow.restaurantShare,
          recipientCode: restaurantPayout.paystackRecipientCode,
          reference,
          reason: `RUN-It order ${orderId} — restaurant payout`,
        });
        escrow = await this.prisma.orderEscrow.update({
          where: { id: escrow.id },
          data: { restaurantTransferReference: reference, restaurantTransferStatus: 'pending' },
        });
      } catch (err) {
        this.logger.error(`Restaurant transfer failed for order ${orderId}: ${(err as Error).message}`);
        transferFailure = err as Error;
      }
    }

    if (!escrow.runnerTransferReference) {
      try {
        const reference = `escrow_${escrow.id}_runner`;
        await this.paystack.initiateTransfer({
          amountKobo: escrow.runnerShare,
          recipientCode: runnerPayout.paystackRecipientCode,
          reference,
          reason: `RUN-It order ${orderId} — runner payout`,
        });
        escrow = await this.prisma.orderEscrow.update({
          where: { id: escrow.id },
          data: { runnerTransferReference: reference, runnerTransferStatus: 'pending' },
        });
      } catch (err) {
        this.logger.error(`Runner transfer failed for order ${orderId}: ${(err as Error).message}`);
        transferFailure = err as Error;
      }
    }

    if (transferFailure) {
      throw new BadGatewayException(
        `One or more transfers failed to initiate for order ${orderId}; retry /release once resolved`,
      );
    }

    // Deliberately NOT one transaction spanning the Paystack calls above:
    // those are external network calls with real-world side effects
    // (money actually moves), and a DB transaction that rolled back *after*
    // a transfer had already been initiated would leave Paystack's and our
    // own records permanently disagreeing with no way to undo the transfer.
    // Each leg's Paystack-call-then-DB-write is already atomic on its own
    // (a single `update`) and safely retriable per-leg (see above) — that
    // per-leg idempotency, not artificial atomicity across an external
    // call, is what makes this safe. See RUNBOOK.md.
    //
    // What *is* pure DB state — the final status flip — is wrapped in one
    // transaction so escrow.status and order.status can never disagree.
    const [releasedEscrow] = await this.prisma.$transaction([
      this.prisma.orderEscrow.update({
        where: { id: escrow.id },
        data: { status: 'released', releasedAt: escrow.releasedAt ?? new Date() },
      }),
      // updateMany, not update: never let this bookkeeping side-effect
      // throw and roll back an otherwise-successful release just because
      // no Order row matched (e.g. an escrow created before Task 9).
      this.prisma.order.updateMany({ where: { id: orderId }, data: { status: 'delivered' } }),
    ]);
    return releasedEscrow;
  }

  async refund(orderId: string): Promise<OrderEscrow> {
    const escrow = await this.findByOrderId(orderId);
    if (escrow.status !== 'held') {
      throw new ConflictException(`Escrow for order ${orderId} is ${escrow.status}, not held — nothing to refund`);
    }

    const studentTransaction = await this.prisma.walletTransaction.findUniqueOrThrow({
      where: { id: escrow.studentWalletTransactionId },
    });

    return this.prisma.$transaction(async (tx) => {
      // Conditional transition guards against two concurrent refund calls
      // both crediting the wallet before either commits.
      const transitioned = await tx.orderEscrow.updateMany({
        where: { id: escrow.id, status: 'held' },
        data: { status: 'refunded' },
      });
      if (transitioned.count === 0) {
        throw new ConflictException(`Escrow for order ${orderId} is not held — nothing to refund`);
      }

      await tx.wallet.update({
        where: { id: studentTransaction.walletId },
        data: { balance: { increment: escrow.grossAmount } },
      });

      await tx.walletTransaction.create({
        data: {
          walletId: studentTransaction.walletId,
          type: 'credit',
          amount: escrow.grossAmount,
          reference: `escrow_refund_${orderId}`,
          status: 'success',
          metadata: { orderId, purpose: 'escrow_refund' },
        },
      });

      // See release()'s comment: updateMany so a missing Order row can
      // never turn a successful refund into a thrown error.
      await tx.order.updateMany({ where: { id: orderId }, data: { status: 'cancelled' } });

      return tx.orderEscrow.findUniqueOrThrow({ where: { id: escrow.id } });
    });
  }

  async findByOrderId(orderId: string): Promise<OrderEscrow> {
    const escrow = await this.prisma.orderEscrow.findUnique({ where: { orderId } });
    if (!escrow) throw new NotFoundException(`No escrow for order ${orderId}`);
    return escrow;
  }

  // Falls back to auto-provisioning a placeholder Vendor for restaurant
  // users that predate Task 9's vendor-profile feature (e.g. Task 8d's
  // demo-seeded restaurant, or any caller that omits vendorId) so the Order
  // row hold() creates always has a valid vendor_id. Also surfaces the
  // vendor's commissionRateOverride (Task 15) so hold() can apply a
  // negotiated rate instead of the platform default.
  private async resolveVendor(
    tx: Prisma.TransactionClient,
    restaurantUserId: string,
    explicitVendorId?: string,
  ): Promise<{ vendorId: string; commissionRateOverride: number | null }> {
    if (explicitVendorId) {
      // Trusts the caller-supplied id as before; a vendor that doesn't
      // exist just falls back to the global default rate rather than
      // failing the hold.
      const vendor = await tx.vendor.findUnique({ where: { id: explicitVendorId } });
      return { vendorId: explicitVendorId, commissionRateOverride: vendor?.commissionRateOverride ?? null };
    }

    const vendor = await tx.vendor.findUnique({ where: { userId: restaurantUserId } });
    if (vendor) return { vendorId: vendor.id, commissionRateOverride: vendor.commissionRateOverride };

    const created = await tx.vendor.create({
      data: { userId: restaurantUserId, businessName: 'Unnamed vendor', category: 'General' },
    });
    return { vendorId: created.id, commissionRateOverride: created.commissionRateOverride };
  }
}
