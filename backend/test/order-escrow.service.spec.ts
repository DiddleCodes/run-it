import {
  BadGatewayException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { OrderEscrowService } from '../src/order-escrow/order-escrow.service';
import {
  createAlertsMock,
  createConfigMock,
  createMatchingServiceMock,
  createNotificationsEmitterMock,
  createPaystackMock,
  createPrismaMock,
} from './support/mocks';

const ESCROW_CONFIG = {
  'escrow.restaurantCommissionRate': 0.15,
  'escrow.defaultDeliveryFeeKobo': 50_000,
  'escrow.restaurantPlatformFeeKobo': 20_000,
  'escrow.runnerDeliveryPayKobo': 20_000,
};

function makeService() {
  const prisma = createPrismaMock();
  const paystack = createPaystackMock();
  const config = createConfigMock(ESCROW_CONFIG);
  const notifications = createNotificationsEmitterMock();
  const matching = createMatchingServiceMock();
  const alerts = createAlertsMock();
  const service = new OrderEscrowService(prisma as any, paystack as any, config as any, notifications as any, matching as any, alerts as any);
  return { service, prisma, paystack, config, notifications, matching, alerts };
}

describe('OrderEscrowService.hold', () => {
  it('rejects a second hold for the same order', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ id: 'e1', status: 'held' });

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        runnerUserId: 'run1',
        grossAmountKobo: 10_000,
      }),
    ).rejects.toThrow(ConflictException);
  });

  it('rejects when the student has no wallet', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue(null);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        runnerUserId: 'run1',
        grossAmountKobo: 10_000,
      }),
    ).rejects.toThrow(NotFoundException);
  });

  it('rejects with 402 when the wallet balance cannot cover the debit', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 500 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 0 });

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        runnerUserId: 'run1',
        grossAmountKobo: 10_000,
      }),
    ).rejects.toThrow(HttpException);
  });

  it('debits the wallet for food subtotal + delivery fee + service fee, writes a ledger entry, and splits per configured rates', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      deliveryFeeKobo: 50_000,
      serviceFeeKobo: 15_000,
    });

    // Total charged = food subtotal (100,000) + delivery fee (50,000) +
    // service fee (15,000) = 165,000.
    expect(prisma.wallet.updateMany).toHaveBeenCalledWith({
      where: { id: 'w1', balance: { gte: 165_000 } },
      data: { balance: { decrement: 165_000 } },
    });
    expect(prisma.walletTransaction.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ walletId: 'w1', type: 'debit', amount: 165_000, status: 'success' }),
      }),
    );

    // 15% commission on the 100,000 food subtotal only (15,000), plus the
    // flat ₦200 (20,000 kobo) platform fee, both deducted from the
    // restaurant's payout. The runner gets a flat ₦200 regardless of the
    // delivery fee. The delivery fee and service fee are both 100% platform
    // revenue — platform keeps whatever's left.
    expect(result.restaurantCommission).toBe(15_000);
    expect(result.restaurantShare).toBe(100_000 - 15_000 - 20_000);
    expect(result.runnerShare).toBe(20_000);
    expect(result.platformFee).toBe(165_000 - result.restaurantShare - result.runnerShare);
    expect(result.platformFee + result.runnerShare + result.restaurantShare).toBe(165_000);
    expect(result.grossAmount).toBe(165_000);
    expect(result.status).toBe('held');
    expect(result.studentWalletTransactionId).toBe('wt1');
  });

  it('keeps the service fee out of the commissionable base — it never touches the restaurant payout', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const withoutServiceFee = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      deliveryFeeKobo: 50_000,
    });

    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    const withServiceFee = await service.hold('order-2', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      deliveryFeeKobo: 50_000,
      serviceFeeKobo: 15_000,
    });

    // Same restaurant payout either way — the ₦150 service fee flows
    // entirely to platform revenue, not diluted 85/15 like the old
    // grossAmountKobo-includes-everything shape did.
    expect(withServiceFee.restaurantShare).toBe(withoutServiceFee.restaurantShare);
    expect(withServiceFee.platformFee).toBe(withoutServiceFee.platformFee + 15_000);
  });

  it('falls back to DEFAULT_DELIVERY_FEE when the caller omits deliveryFeeKobo', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
    });

    // ESCROW_CONFIG's defaultDeliveryFeeKobo is 50,000 (₦500).
    expect(result.grossAmount).toBe(150_000);
    expect(prisma.wallet.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ balance: { gte: 150_000 } }) }),
    );
  });

  it("uses the vendor's commissionRateOverride instead of the global rate when set", async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    // Negotiated 10% rate instead of the global 15% default.
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: 0.1 });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      deliveryFeeKobo: 0,
    });

    expect(result.restaurantShare).toBe(100_000 - 10_000 - 20_000);
    expect(result.platformFee).toBe(100_000 - result.restaurantShare - result.runnerShare);
  });

  it("persists the single order-level note, and no longer accepts per-item notes", async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      note: 'Leave at the gate, please',
    });

    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ note: 'Leave at the gate, please' }),
      }),
    );
  });

  it('auto-provisions a placeholder vendor for a restaurant user with no vendor profile, and creates the Order row', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 100_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue(null);
    prisma.vendor.create.mockResolvedValue({ id: 'auto-vendor-1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 10_000,
      items: [{ name: 'Jollof', priceKobo: 3_000, quantity: 2 }],
    });

    expect(prisma.vendor.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ userId: 'r1' }) }),
    );
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: 'order-1' },
        create: expect.objectContaining({
          id: 'order-1',
          vendorId: 'auto-vendor-1',
          status: 'placed',
          // Default delivery fee (50,000, per ESCROW_CONFIG) added on top of
          // the 10,000 food subtotal since deliveryFeeKobo wasn't supplied.
          totalAmount: 60_000,
        }),
      }),
    );
    expect(prisma.orderItem.createMany).toHaveBeenCalledWith(
      expect.objectContaining({
        data: [
          expect.objectContaining({
            orderId: 'order-1',
            nameSnapshot: 'Jollof',
            priceSnapshot: 3_000,
            quantity: 2,
          }),
        ],
      }),
    );
  });

  it('converts a DB-level unique-constraint race on order_escrows.order_id into a clean 409, not a raw 500', async () => {
    // Simulates two concurrent hold() calls for the same orderId both
    // passing the earlier findUnique pre-check (both see no existing
    // escrow) and both reaching orderEscrow.create — exactly the race the
    // DB's unique constraint (not application logic) has to catch. Task 9b
    // requirement: "a retried hold request for the same order must not
    // create a duplicate."
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 100_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1' });
    prisma.orderEscrow.create.mockRejectedValue(
      new Prisma.PrismaClientKnownRequestError('Unique constraint failed on the fields: (`order_id`)', {
        code: 'P2002',
        clientVersion: 'test',
      }),
    );

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        runnerUserId: 'run1',
        grossAmountKobo: 10_000,
      }),
    ).rejects.toThrow(ConflictException);
  });

  // Task 21a: the broadcast-and-claim flow holds an order with no runner
  // resolved up front at all.
  it('holds an order with no runner attached when runnerUserId is omitted', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 100_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      grossAmountKobo: 10_000,
    });

    expect(result.runnerUserId).toBeNull();
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ runnerUserId: null }) }),
    );
  });

  it('does not swallow an unrelated database error as a conflict', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 100_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1' });
    prisma.orderEscrow.create.mockRejectedValue(new Error('connection reset'));

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        runnerUserId: 'run1',
        grossAmountKobo: 10_000,
      }),
    ).rejects.toThrow('connection reset');
  });
});

describe('OrderEscrowService.claim', () => {
  const unclaimedEscrow = { id: 'esc1', orderId: 'order-1', runnerUserId: null };
  const runner = { sub: 'runner-1', accountType: 'runner' as const, role: 'user' as const };

  // Every test below the KYC-gating group is exercising claim() *after*
  // that gate — approved is the default so those tests keep testing what
  // they were written to test, not re-litigating the gate itself.
  function approveKyc(prisma: ReturnType<typeof createPrismaMock>) {
    prisma.runnerKyc.findUnique.mockResolvedValue({ status: 'approved' });
  }

  it('rejects a non-runner account', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(unclaimedEscrow);

    await expect(
      service.claim('order-1', { sub: 'student-1', accountType: 'student', role: 'user' }),
    ).rejects.toThrow(ForbiddenException);
  });

  // Task 29: the real, backend-enforced hard gate — see
  // OrderEscrowService.claim's own doc comment on why this is a fresh DB
  // read rather than trusting a claim embedded in the JWT.
  describe('KYC gating', () => {
    it('rejects a runner who has never submitted KYC (no RunnerKyc row)', async () => {
      const { service, prisma } = makeService();
      prisma.runnerKyc.findUnique.mockResolvedValue(null);

      await expect(service.claim('order-1', runner)).rejects.toThrow(ForbiddenException);
      // Never even looks at the order/escrow — the gate runs first.
      expect(prisma.orderEscrow.findUnique).not.toHaveBeenCalled();
    });

    it('rejects a runner whose KYC is still pending review', async () => {
      const { service, prisma } = makeService();
      prisma.runnerKyc.findUnique.mockResolvedValue({ status: 'pending' });

      await expect(service.claim('order-1', runner)).rejects.toThrow(ForbiddenException);
      expect(prisma.orderEscrow.findUnique).not.toHaveBeenCalled();
    });

    it('rejects a runner whose KYC was rejected', async () => {
      const { service, prisma } = makeService();
      prisma.runnerKyc.findUnique.mockResolvedValue({ status: 'rejected' });

      await expect(service.claim('order-1', runner)).rejects.toThrow(ForbiddenException);
      expect(prisma.orderEscrow.findUnique).not.toHaveBeenCalled();
    });

    it('allows a runner whose KYC is approved through to the normal claim flow', async () => {
      const { service, prisma } = makeService();
      approveKyc(prisma);
      prisma.orderEscrow.findUnique.mockResolvedValue({ ...unclaimedEscrow, runnerUserId: 'runner-1' });

      const result = await service.claim('order-1', runner);

      expect(result.runnerUserId).toBe('runner-1');
    });
  });

  it('throws if the escrow does not exist', async () => {
    const { service, prisma } = makeService();
    approveKyc(prisma);
    prisma.orderEscrow.findUnique.mockResolvedValue(null);

    await expect(service.claim('order-x', runner)).rejects.toThrow(NotFoundException);
  });

  it("is idempotent for the same runner's own already-successful claim", async () => {
    const { service, prisma } = makeService();
    approveKyc(prisma);
    const alreadyMine = { ...unclaimedEscrow, runnerUserId: 'runner-1' };
    prisma.orderEscrow.findUnique.mockResolvedValue(alreadyMine);

    const result = await service.claim('order-1', runner);

    expect(result).toEqual(alreadyMine);
    expect(prisma.orderEscrow.updateMany).not.toHaveBeenCalled();
  });

  it('rejects claiming an order that is not in a claimable status', async () => {
    const { service, prisma } = makeService();
    approveKyc(prisma);
    prisma.orderEscrow.findUnique.mockResolvedValue(unclaimedEscrow);
    prisma.order.findUniqueOrThrow.mockResolvedValue({ id: 'order-1', status: 'placed' });

    await expect(service.claim('order-1', runner)).rejects.toThrow(ConflictException);
    expect(prisma.orderEscrow.updateMany).not.toHaveBeenCalled();
  });

  it('claims an unclaimed order: sets both Order and OrderEscrow runnerUserId, cancels pending matching jobs', async () => {
    const { service, prisma, matching } = makeService();
    approveKyc(prisma);
    prisma.orderEscrow.findUnique
      .mockResolvedValueOnce(unclaimedEscrow) // initial lookup
      .mockResolvedValueOnce({ ...unclaimedEscrow, runnerUserId: 'runner-1' }); // re-fetch after claim
    prisma.order.findUniqueOrThrow.mockResolvedValue({ id: 'order-1', status: 'preparing' });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    prisma.order.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.claim('order-1', runner);

    expect(prisma.orderEscrow.updateMany).toHaveBeenCalledWith({
      where: { orderId: 'order-1', runnerUserId: null },
      data: { runnerUserId: 'runner-1' },
    });
    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { id: 'order-1', runnerUserId: null },
      data: { runnerUserId: 'runner-1' },
    });
    expect(matching.cancelPendingJobs).toHaveBeenCalledWith('order-1');
    expect(result.runnerUserId).toBe('runner-1');
  });

  it('returns a distinct ORDER_ALREADY_CLAIMED conflict when the conditional update affects zero rows', async () => {
    const { service, prisma, matching } = makeService();
    approveKyc(prisma);
    prisma.orderEscrow.findUnique.mockResolvedValue(unclaimedEscrow);
    prisma.order.findUniqueOrThrow.mockResolvedValue({ id: 'order-1', status: 'preparing' });
    // Simulates losing the race: another runner's claim committed first,
    // so this conditional update — scoped to runnerUserId: null — affects
    // no rows even though the pre-check above saw an unclaimed order.
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.claim('order-1', runner)).rejects.toMatchObject({
      status: 409,
      response: expect.objectContaining({ code: 'ORDER_ALREADY_CLAIMED' }),
    });
    expect(prisma.order.updateMany).not.toHaveBeenCalled();
    expect(matching.cancelPendingJobs).not.toHaveBeenCalled();
  });
});

describe('OrderEscrowService.release', () => {
  const heldEscrow = {
    id: 'esc1',
    orderId: 'order-1',
    status: 'held',
    restaurantUserId: 'r1',
    runnerUserId: 'run1',
    grossAmount: 10_000,
    platformFee: 1_500,
    restaurantShare: 7_000,
    runnerShare: 1_500,
    restaurantTransferReference: null,
    runnerTransferReference: null,
    releasedAt: null,
  };

  it('throws if the escrow does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    await expect(service.release('order-x')).rejects.toThrow(NotFoundException);
  });

  it('refuses to release an escrow that was already refunded', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow, status: 'refunded' });
    await expect(service.release('order-1')).rejects.toThrow(ConflictException);
  });

  // Task 21a: defensive only — EscrowPartyGuard's 'runner' check on the
  // /release route can never actually let a null-runnerUserId escrow reach
  // here (see this guard's own comment in release()), but this proves the
  // fallback is safe rather than crashing on a null payoutAccount lookup.
  it('rejects releasing an escrow with no runner attached', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow, runnerUserId: null });
    await expect(service.release('order-1')).rejects.toThrow(UnprocessableEntityException);
  });

  it('rejects when the restaurant has no payout account on file', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.payoutAccount.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 0 });

    await expect(service.release('order-1')).rejects.toThrow(UnprocessableEntityException);
  });

  // Task 33: a runner's earnings now land in a wallet, not a bank transfer
  // — a missing Wallet row (should never happen post-backfill/signup
  // provisioning) is the new failure mode replacing the old "no payout
  // account" check for this leg.
  it('rejects when the runner has no wallet on file', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue(null);

    await expect(service.release('order-1')).rejects.toThrow(UnprocessableEntityException);
  });

  it('transfers the restaurant share via Paystack and credits the runner share to their wallet, marking the escrow released', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 0 });
    paystack.initiateTransfer.mockResolvedValue({ reference: 'ref', transferCode: 'TRF_x', status: 'pending' });

    let escrowState = { ...heldEscrow };
    prisma.orderEscrow.update.mockImplementation(({ data }: any) => {
      escrowState = { ...escrowState, ...data };
      return Promise.resolve(escrowState);
    });
    prisma.orderEscrow.updateMany.mockImplementation(({ data }: any) => {
      escrowState = { ...escrowState, ...data };
      return Promise.resolve({ count: 1 });
    });
    prisma.orderEscrow.findUniqueOrThrow.mockImplementation(() => Promise.resolve(escrowState));

    const result = await service.release('order-1');

    // The restaurant leg is completely untouched — still a real Paystack
    // transfer, still the only leg that ever calls it.
    expect(paystack.initiateTransfer).toHaveBeenCalledWith(
      expect.objectContaining({ amountKobo: 7_000, recipientCode: 'RCP_restaurant', reference: 'escrow_esc1_restaurant' }),
    );
    expect(paystack.initiateTransfer).toHaveBeenCalledTimes(1);

    // The runner leg is a wallet credit instead — no Paystack call at all.
    expect(prisma.wallet.update).toHaveBeenCalledWith({
      where: { id: 'wallet-run1' },
      data: { balance: { increment: 1_500 } },
    });
    expect(prisma.walletTransaction.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        walletId: 'wallet-run1',
        type: 'credit',
        amount: 1_500,
        reference: 'escrow_esc1_runner_wallet_credit',
        status: 'success',
        metadata: expect.objectContaining({ orderId: 'order-1', purpose: 'runner_delivery_earnings' }),
      }),
    });

    expect(result.status).toBe('released');
    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'delivered', deliveredAt: expect.any(Date) },
    });
  });

  it('does not re-transfer the restaurant leg if already initiated, but still credits the runner leg (safe partial retry)', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({
      ...heldEscrow,
      restaurantTransferReference: 'escrow_esc1_restaurant', // already initiated
    });
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 0 });

    let escrowState = { ...heldEscrow, restaurantTransferReference: 'escrow_esc1_restaurant' };
    prisma.orderEscrow.update.mockImplementation(({ data }: any) => {
      escrowState = { ...escrowState, ...data };
      return Promise.resolve(escrowState);
    });
    prisma.orderEscrow.updateMany.mockImplementation(({ data }: any) => {
      escrowState = { ...escrowState, ...data };
      return Promise.resolve({ count: 1 });
    });
    prisma.orderEscrow.findUniqueOrThrow.mockImplementation(() => Promise.resolve(escrowState));

    await service.release('order-1');

    expect(paystack.initiateTransfer).not.toHaveBeenCalled();
    expect(prisma.wallet.update).toHaveBeenCalledWith({
      where: { id: 'wallet-run1' },
      data: { balance: { increment: 1_500 } },
    });
  });

  // Task 33's own retry-safety requirement: release() called again for an
  // order whose runner leg already settled must not double-credit — the
  // conditional `updateMany` guard (`runnerTransferReference: null`) is
  // what makes this safe, mirroring the same shape claim() uses for the
  // runner-assignment race.
  it('does not double-credit the runner wallet on a full retry after both legs already settled', async () => {
    const { service, prisma, paystack } = makeService();
    const alreadyReleased = {
      ...heldEscrow,
      restaurantTransferReference: 'escrow_esc1_restaurant',
      runnerTransferReference: 'escrow_esc1_runner_wallet_credit',
    };
    prisma.orderEscrow.findUnique.mockResolvedValue(alreadyReleased);
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 1_500 });
    prisma.orderEscrow.update.mockImplementation(({ data }: any) => Promise.resolve({ ...alreadyReleased, ...data }));

    const result = await service.release('order-1');

    expect(paystack.initiateTransfer).not.toHaveBeenCalled();
    expect(prisma.wallet.update).not.toHaveBeenCalled();
    expect(prisma.walletTransaction.create).not.toHaveBeenCalled();
    expect(prisma.orderEscrow.updateMany).not.toHaveBeenCalled();
    expect(result.status).toBe('released');
  });

  // Task 31: a transfer-initiation failure is real money stuck mid-payout
  // — previously logged only. Confirms the real-time alert now fires
  // (Sentry capture is exercised the same way but isn't observable through
  // this mock; see the live-proof evidence in the Task 31 report instead).
  it('alerts on a restaurant transfer failure instead of only logging it', async () => {
    const { service, prisma, paystack, alerts } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 0 });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    prisma.orderEscrow.findUniqueOrThrow.mockResolvedValue({ ...heldEscrow, runnerTransferReference: 'escrow_esc1_runner_wallet_credit' });
    paystack.initiateTransfer.mockRejectedValue(new Error('Paystack transfer API timed out'));

    await expect(service.release('order-1')).rejects.toThrow(BadGatewayException);

    expect(alerts.send).toHaveBeenCalledWith(
      'Restaurant payout transfer failed to initiate for order order-1',
      expect.objectContaining({ orderId: 'order-1', leg: 'restaurant' }),
    );
  });

  // Task 33: the runner leg's new failure mode is a DB error inside the
  // wallet-credit transaction, not a Paystack rejection — same alert
  // channel, different trigger.
  it('alerts on a runner wallet-credit failure instead of only logging it', async () => {
    const { service, prisma, paystack, alerts } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.payoutAccount.findUnique.mockResolvedValue({ paystackRecipientCode: 'RCP_restaurant' });
    prisma.wallet.findUnique.mockResolvedValue({ id: 'wallet-run1', userId: 'run1', balance: 0 });
    prisma.orderEscrow.update.mockImplementation(({ data }: any) => Promise.resolve({ ...heldEscrow, ...data }));
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    paystack.initiateTransfer.mockResolvedValue({ reference: 'ref', transferCode: 'TRF_x', status: 'pending' });
    prisma.wallet.update.mockRejectedValue(new Error('DB connection lost'));

    await expect(service.release('order-1')).rejects.toThrow(BadGatewayException);

    expect(alerts.send).toHaveBeenCalledWith(
      'Runner wallet credit failed for order order-1',
      expect.objectContaining({ orderId: 'order-1', leg: 'runner', error: 'DB connection lost' }),
    );
  });
});

describe('OrderEscrowService.refund', () => {
  const heldEscrow = {
    id: 'esc1',
    orderId: 'order-1',
    status: 'held',
    studentWalletTransactionId: 'wt1',
    grossAmount: 10_000,
  };

  it('throws if the escrow does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    await expect(service.refund('order-x')).rejects.toThrow(NotFoundException);
  });

  it('refuses to refund an escrow that has already been released', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow, status: 'released' });
    await expect(service.refund('order-1')).rejects.toThrow(ConflictException);
  });

  it('credits the wallet back and never calls the Paystack transfer API', async () => {
    const { service, prisma, paystack } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.walletTransaction.findUniqueOrThrow.mockResolvedValue({ id: 'wt1', walletId: 'w1' });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    prisma.orderEscrow.findUniqueOrThrow.mockResolvedValue({ ...heldEscrow, status: 'refunded' });

    const result = await service.refund('order-1');

    expect(prisma.wallet.update).toHaveBeenCalledWith({
      where: { id: 'w1' },
      data: { balance: { increment: 10_000 } },
    });
    expect(prisma.walletTransaction.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ walletId: 'w1', type: 'credit', amount: 10_000, status: 'success' }),
      }),
    );
    expect(paystack.initiateTransfer).not.toHaveBeenCalled();
    expect(result.status).toBe('refunded');
    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'cancelled', cancelledAt: expect.any(Date) },
    });
  });
});
