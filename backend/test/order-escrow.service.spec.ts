import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  ForbiddenException,
  HttpException,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { runnerDisplayName } from '../src/orders/orders.service';
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
  'escrow.serviceFeeRate': 0.05,
};

// Task 70: hold() prices every order from real menu rows. This stands in
// for the menu_items table: `food-<kobo>` is a non-main item priced at
// exactly <kobo>; `m*` ids are ₦1,500 main meals, `s*` ₦500 sides — all
// available, all on vendor v1 owned by restaurant user r1.
function catalogItem(id: string) {
  const food = /^food-(\d+)$/.exec(id);
  return {
    id,
    name: `Item ${id}`,
    price: food ? Number(food[1]) : id.startsWith('m') ? 150_000 : 50_000,
    isAvailable: true,
    isMainMeal: id.startsWith('m'),
    vendorId: 'v1',
    vendor: { userId: 'r1' },
  };
}

// One menu line worth exactly [kobo] of food.
function food(kobo: number) {
  return { menuItemId: `food-${kobo}`, quantity: 1 };
}

function makeService(extraConfig: Record<string, unknown> = {}) {
  const prisma = createPrismaMock();
  const paystack = createPaystackMock();
  const config = createConfigMock({ ...ESCROW_CONFIG, ...extraConfig });
  const notifications = createNotificationsEmitterMock();
  const matching = createMatchingServiceMock();
  const alerts = createAlertsMock();
  prisma.menuItem.findMany.mockImplementation(async ({ where }: any) => (where.id.in as string[]).map(catalogItem));
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
        items: [food(10_000)],
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
        items: [food(10_000)],
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
        items: [food(10_000)],
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
      items: [food(100_000)],
      deliveryFeeKobo: 50_000,
      serviceFeeKobo: 5_000,
    });

    // Total charged = food subtotal (100,000) + delivery fee (50,000) +
    // service fee (15,000) = 165,000.
    expect(prisma.wallet.updateMany).toHaveBeenCalledWith({
      where: { id: 'w1', balance: { gte: 155_000 } },
      data: { balance: { decrement: 155_000 } },
    });
    expect(prisma.walletTransaction.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ walletId: 'w1', type: 'debit', amount: 155_000, status: 'success' }),
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
    expect(result.platformFee).toBe(155_000 - result.restaurantShare - result.runnerShare);
    expect(result.platformFee + result.runnerShare + result.restaurantShare).toBe(155_000);
    expect(result.grossAmount).toBe(155_000);
    expect(result.status).toBe('held');
    expect(result.studentWalletTransactionId).toBe('wt1');
  });

  it('keeps the service fee out of the commissionable base — it never touches the restaurant payout', async () => {
    async function holdWithRate(rate: number) {
      const { service, prisma } = makeService({ 'escrow.serviceFeeRate': rate });
      prisma.orderEscrow.findUnique.mockResolvedValue(null);
      prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
      prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
      prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
      prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
      prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));
      return service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [food(100_000)] });
    }

    const withoutServiceFee = await holdWithRate(0);
    const withServiceFee = await holdWithRate(0.05);

    // Same restaurant payout and runner pay either way — the 5% (₦50)
    // service fee flows entirely to platform revenue.
    expect(withServiceFee.restaurantShare).toBe(withoutServiceFee.restaurantShare);
    expect(withServiceFee.runnerShare).toBe(withoutServiceFee.runnerShare);
    expect(withServiceFee.platformFee).toBe(withoutServiceFee.platformFee + 5_000);
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
      items: [food(100_000)],
    });

    // ESCROW_CONFIG's defaultDeliveryFeeKobo is 50,000 (₦500), plus the
    // 5% (5,000) service fee on the 100,000 food subtotal.
    expect(result.grossAmount).toBe(155_000);
    expect(prisma.wallet.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ balance: { gte: 155_000 } }) }),
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
      items: [food(100_000)],
    });

    expect(result.restaurantShare).toBe(100_000 - 10_000 - 20_000);
    expect(result.platformFee).toBe(result.grossAmount - result.restaurantShare - result.runnerShare);
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
      items: [food(100_000)],
      note: 'Leave at the gate, please',
    });

    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ note: 'Leave at the gate, please' }),
      }),
    );
  });

  it('Task 70: snapshots the real menu name/price onto the order, never the client-sent ones', async () => {
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
      // A tampered line claiming the ₦1,500 main costs ₦30 under another name.
      items: [{ menuItemId: 'm1', name: 'Totally cheap', priceKobo: 3_000, quantity: 2 }],
    });

    expect(prisma.orderItem.createMany).toHaveBeenCalledWith({
      data: [{ orderId: 'order-1', menuItemId: 'm1', nameSnapshot: 'Item m1', priceSnapshot: 150_000, quantity: 2 }],
    });
    // 2 x 150,000 food + 50,000 delivery + 15,000 (5%) service = 365,000.
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ totalAmount: 365_000 }) }),
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
        items: [food(10_000)],
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
      items: [food(10_000)],
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
        items: [food(10_000)],
      }),
    ).rejects.toThrow('connection reset');
  });
});

describe('OrderEscrowService.hold — Task 67 Pay on Delivery launch switch (off by default)', () => {
  it('rejects a Pay on Delivery attempt while POD is switched off, even for an opted-in restaurant', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null, payAtDeliveryEnabled: true });

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 100_000,
        items: [food(100_000)],
        paymentMethod: 'pay_on_delivery',
      }),
    ).rejects.toThrow(new ForbiddenException("Pay on Delivery isn't available yet"));
    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(prisma.order.upsert).not.toHaveBeenCalled();
    expect(prisma.orderEscrow.create).not.toHaveBeenCalled();
  });

  it('leaves wallet orders completely unaffected while POD is switched off', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null, payAtDeliveryEnabled: false });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      grossAmountKobo: 100_000,
      items: [food(100_000)],
    });

    expect(result.studentWalletTransactionId).toBe('wt1');
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ paymentMethod: 'wallet' }) }),
    );
  });
});

// Task 67: POD ships switched off (features.podEnabled) — these prove the
// feature itself still works exactly as Task 47 built it once switched on.
describe('OrderEscrowService.hold — Task 47 Pay on Delivery (switched on)', () => {
  const POD_ON = { 'features.podEnabled': true };

  it('never touches the wallet at all for a Pay on Delivery order', async () => {
    const { service, prisma } = makeService(POD_ON);
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null, payAtDeliveryEnabled: true });
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      runnerUserId: 'run1',
      grossAmountKobo: 100_000,
      items: [food(100_000)],
      deliveryFeeKobo: 50_000,
      paymentMethod: 'pay_on_delivery',
    });

    expect(prisma.wallet.findUnique).not.toHaveBeenCalled();
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
    expect(prisma.walletTransaction.create).not.toHaveBeenCalled();
    expect(result.studentWalletTransactionId).toBeNull();
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ paymentMethod: 'pay_on_delivery' }) }),
    );
    // The restaurant/runner payout math is identical to a wallet order —
    // Pay on Delivery only changes who funds it and when.
    expect(result.restaurantShare).toBeGreaterThan(0);
    expect(result.runnerShare).toBe(20_000);
  });

  it("rejects a Pay on Delivery attempt when the restaurant hasn't opted in", async () => {
    const { service, prisma } = makeService(POD_ON);
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null, payAtDeliveryEnabled: false });

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 100_000,
        items: [food(100_000)],
        paymentMethod: 'pay_on_delivery',
      }),
    ).rejects.toThrow(ForbiddenException);
    expect(prisma.order.upsert).not.toHaveBeenCalled();
  });

  it('rejects a Pay on Delivery attempt over the order-value cap even for an opted-in restaurant', async () => {
    const { service, prisma } = makeService(POD_ON);
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null, payAtDeliveryEnabled: true });

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 960_000,
        items: [food(960_000)],
        deliveryFeeKobo: 50_000,
        paymentMethod: 'pay_on_delivery',
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.order.upsert).not.toHaveBeenCalled();
  });
});

describe('OrderEscrowService.hold — Task 66 Group Ordering', () => {
  function mainMealItem(id: string, quantity: number) {
    return { menuItemId: id, name: `Main ${id}`, priceKobo: 150_000, quantity };
  }
  function sideItem(id: string, quantity: number) {
    return { menuItemId: id, name: `Side ${id}`, priceKobo: 50_000, quantity };
  }

  it('rejects a standard order with 3 main meals', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 300_000,
        items: [mainMealItem('m1', 1), mainMealItem('m2', 1), mainMealItem('m3', 1)],
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.order.upsert).not.toHaveBeenCalled();
    // Fails before touching the wallet — a rejected basket never debits.
    expect(prisma.wallet.findUnique).not.toHaveBeenCalled();
  });

  it('rejects a standard order whose main-meal quantities sum past the cap, even across distinct items', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 300_000,
        // One main-meal menu item at quantity 3 — same real cap violation
        // as three distinct main-meal lines.
        items: [mainMealItem('m1', 3)],
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('allows a standard order with exactly 2 main meals (cap unchanged)', async () => {
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
      grossAmountKobo: 300_000,
      items: [mainMealItem('m1', 1), mainMealItem('m2', 1)],
    });

    expect(result).toBeDefined();
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ orderType: 'standard' }) }),
    );
  });

  it('rejects a group order with 5 main meals', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 500_000,
        orderType: 'group',
        items: [mainMealItem('m1', 5)],
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.order.upsert).not.toHaveBeenCalled();
  });

  it('allows a group order with exactly 4 main meals and charges the ₦150 (15,000 kobo) surcharge on top of the flat delivery fee', async () => {
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
      grossAmountKobo: 600_000,
      // Flutter always sends the BASE flat fee (₦500) — the group
      // surcharge is applied server-side regardless, per hold()'s own doc
      // comment.
      deliveryFeeKobo: 50_000,
      orderType: 'group',
      items: [mainMealItem('m1', 1), mainMealItem('m2', 1), mainMealItem('m3', 1), mainMealItem('m4', 1)],
    });

    // Total charged = food subtotal (4 x 150,000 = 600,000) + delivery fee
    // (50,000 base + 15,000 group surcharge = 65,000) + 5% service fee
    // (30,000) = 695,000.
    expect(prisma.wallet.updateMany).toHaveBeenCalledWith({
      where: { id: 'w1', balance: { gte: 695_000 } },
      data: { balance: { decrement: 695_000 } },
    });
    expect(result.grossAmount).toBe(695_000);
    expect(prisma.order.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ create: expect.objectContaining({ orderType: 'group' }) }),
    );
  });

  it('applies the group surcharge even when the caller omits deliveryFeeKobo (defaults to the configured base fee)', async () => {
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
      grossAmountKobo: 150_000,
      orderType: 'group',
      items: [mainMealItem('m1', 1)],
    });

    // Base default (50,000) + group surcharge (15,000) = 65,000, plus the
    // 5% (7,500) service fee.
    expect(result.grossAmount).toBe(150_000 + 65_000 + 7_500);
  });

  it('a standard order is completely unaffected: unchanged ₦500 (50,000 kobo) delivery fee, no surcharge', async () => {
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
      grossAmountKobo: 150_000,
      items: [mainMealItem('m1', 1)],
    });

    expect(result.grossAmount).toBe(150_000 + 50_000 + 7_500);
  });

  it('does not count side/drink/dessert items toward the main-meal cap', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    // Only m1/m2 are real main meals; s1/s2/s3 resolve to isMainMeal:
    // false in the menu catalog, so 10 sides never count.
    prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      grossAmountKobo: 800_000,
      items: [
        mainMealItem('m1', 1),
        mainMealItem('m2', 1),
        sideItem('s1', 5),
        sideItem('s2', 3),
        sideItem('s3', 2),
      ],
    });

    expect(result).toBeDefined();
  });

  it('Task 70: rejects a line with no real menu item outright — nothing unverifiable can be ordered or priced', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue(null);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        items: [{ name: 'Jollof Rice', priceKobo: 150_000, quantity: 3 }] as any,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.wallet.findUnique).not.toHaveBeenCalled();
    expect(prisma.order.upsert).not.toHaveBeenCalled();
  });
});

describe('OrderEscrowService.hold — Task 70 server-authoritative pricing + 5% service fee', () => {
  function readyToCharge(extraConfig: Record<string, unknown> = {}) {
    const ctx = makeService(extraConfig);
    ctx.prisma.orderEscrow.findUnique.mockResolvedValue(null);
    ctx.prisma.wallet.findUnique.mockResolvedValue({ id: 'w1', userId: 's1', balance: 1_000_000 });
    ctx.prisma.wallet.updateMany.mockResolvedValue({ count: 1 });
    ctx.prisma.walletTransaction.create.mockResolvedValue({ id: 'wt1' });
    ctx.prisma.vendor.findUnique.mockResolvedValue({ id: 'v1', commissionRateOverride: null });
    ctx.prisma.orderEscrow.create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'esc1', ...data }));
    return ctx;
  }

  it('₦1,000 of food, solo: charges exactly ₦1,550 and splits restaurant ₦650 / runner ₦200 / platform ₦700', async () => {
    const { service, prisma } = readyToCharge();

    const result = await service.hold('order-1', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      grossAmountKobo: 100_000,
      deliveryFeeKobo: 50_000,
      serviceFeeKobo: 5_000,
      items: [food(100_000)],
    });

    expect(prisma.wallet.updateMany).toHaveBeenCalledWith({
      where: { id: 'w1', balance: { gte: 155_000 } },
      data: { balance: { decrement: 155_000 } },
    });
    expect(result.grossAmount).toBe(155_000);
    expect(result.restaurantShare).toBe(65_000);
    expect(result.runnerShare).toBe(20_000);
    expect(result.platformFee).toBe(70_000);
  });

  it('rejects a tampered serviceFeeKobo — nothing is charged', async () => {
    const { service, prisma } = readyToCharge();

    await expect(
      service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', serviceFeeKobo: 100, items: [food(100_000)] }),
    ).rejects.toThrow(new BadRequestException('The service fee for this order is ₦50, not ₦1 — refresh your basket and try again.'));
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
    expect(prisma.order.upsert).not.toHaveBeenCalled();
  });

  it('rejects a tampered deliveryFeeKobo (e.g. zero) — the flat fee is server-set', async () => {
    const { service, prisma } = readyToCharge();

    await expect(
      service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', deliveryFeeKobo: 0, items: [food(100_000)] }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('rejects (409) a subtotal claim that no longer matches real menu prices, instead of charging a different amount', async () => {
    const { service, prisma } = readyToCharge();

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        grossAmountKobo: 1_000, // claims ₦10 for a ₦1,500 main
        items: [{ menuItemId: 'm1', quantity: 1 }],
      }),
    ).rejects.toThrow(ConflictException);
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('rejects an item that is no longer available', async () => {
    const { service, prisma } = readyToCharge();
    prisma.menuItem.findMany.mockResolvedValue([{ ...catalogItem('m1'), name: 'Jollof', isAvailable: false }]);

    await expect(
      service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [{ menuItemId: 'm1', quantity: 1 }] }),
    ).rejects.toThrow(new BadRequestException('Jollof is no longer available — remove it to continue.'));
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('Task 72: one unavailable line rejects the WHOLE order — never dropped, never partially placed', async () => {
    const { service, prisma } = readyToCharge();
    prisma.menuItem.findMany.mockResolvedValue([
      catalogItem('m1'),
      { ...catalogItem('s1'), name: 'Chapman', isAvailable: false },
      catalogItem('s2'),
    ]);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        // A stale client basket still listing the item as orderable.
        items: [
          { menuItemId: 'm1', quantity: 1 },
          { menuItemId: 's1', quantity: 2 },
          { menuItemId: 's2', quantity: 1 },
        ],
      }),
    ).rejects.toThrow(new BadRequestException('Chapman is no longer available — remove it to continue.'));
    expect(prisma.wallet.findUnique).not.toHaveBeenCalled();
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
    expect(prisma.order.upsert).not.toHaveBeenCalled();
    expect(prisma.orderItem.createMany).not.toHaveBeenCalled();
    expect(prisma.orderEscrow.create).not.toHaveBeenCalled();
  });

  it("rejects an item that doesn't exist (e.g. deleted from the menu)", async () => {
    const { service, prisma } = readyToCharge();
    prisma.menuItem.findMany.mockResolvedValue([]);

    await expect(
      service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [{ menuItemId: 'gone', quantity: 1 }] }),
    ).rejects.toThrow(BadRequestException);
  });

  it("rejects items from another restaurant's menu (a cheaper menu can't be billed to this one)", async () => {
    const { service, prisma } = readyToCharge();
    prisma.menuItem.findMany.mockResolvedValue([{ ...catalogItem('m1'), vendorId: 'v2', vendor: { userId: 'r2' } }]);

    await expect(
      service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [{ menuItemId: 'm1', quantity: 1 }] }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.wallet.updateMany).not.toHaveBeenCalled();
  });

  it('rejects a basket that mixes two restaurants', async () => {
    const { service, prisma } = readyToCharge();
    prisma.menuItem.findMany.mockResolvedValue([catalogItem('m1'), { ...catalogItem('s1'), vendorId: 'v2' }]);

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        items: [
          { menuItemId: 'm1', quantity: 1 },
          { menuItemId: 's1', quantity: 1 },
        ],
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('rejects a vendorId that does not own the items', async () => {
    const { service } = readyToCharge();

    await expect(
      service.hold('order-1', {
        studentUserId: 's1',
        restaurantUserId: 'r1',
        vendorId: 'someone-else',
        items: [{ menuItemId: 'm1', quantity: 1 }],
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('a group order still adds exactly the ₦150 surcharge — the 5% fee is on food only', async () => {
    const { service } = readyToCharge();

    const solo = await service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [food(100_000)] });
    const { service: service2 } = readyToCharge();
    const group = await service2.hold('order-2', {
      studentUserId: 's1',
      restaurantUserId: 'r1',
      orderType: 'group',
      items: [food(100_000)],
    });

    expect(group.grossAmount - solo.grossAmount).toBe(15_000);
    expect(group.restaurantShare).toBe(solo.restaurantShare);
  });

  it('honours a configured SERVICE_FEE_RATE', async () => {
    const { service } = readyToCharge({ 'escrow.serviceFeeRate': 0.1 });

    const result = await service.hold('order-1', { studentUserId: 's1', restaurantUserId: 'r1', items: [food(100_000)] });

    expect(result.grossAmount).toBe(100_000 + 50_000 + 10_000);
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

  describe('push notifications on a successful claim', () => {
    const claimedOrder = {
      id: 'order-1790832731040039',
      status: 'preparing',
      vendorId: 'vendor-1',
      studentUserId: 'student-1',
    };

    function winClaim(prisma: ReturnType<typeof createPrismaMock>) {
      approveKyc(prisma);
      prisma.orderEscrow.findUnique
        .mockResolvedValueOnce({ ...unclaimedEscrow, orderId: claimedOrder.id })
        .mockResolvedValueOnce({ ...unclaimedEscrow, orderId: claimedOrder.id, runnerUserId: 'runner-1' });
      prisma.order.findUniqueOrThrow.mockResolvedValue(claimedOrder);
      prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
      prisma.order.updateMany.mockResolvedValue({ count: 1 });
      prisma.vendor.findUnique.mockResolvedValue({ businessName: 'Golden Crust Bakery' });
      prisma.user.findUnique.mockResolvedValue({ name: 'Tobi Adeyemi' });
    }

    it('confirms the claim to the runner and tells the student who is on it', async () => {
      const { service, prisma, notifications } = makeService();
      winClaim(prisma);

      await service.claim(claimedOrder.id, runner);

      expect(notifications.emit).toHaveBeenCalledWith({
        type: 'runner_claim_confirmed',
        recipientUserId: 'runner-1',
        title: 'Job confirmed',
        body: 'Order #31040039 is yours. Head to Golden Crust Bakery for pickup.',
        data: { orderId: claimedOrder.id },
      });
      expect(notifications.emit).toHaveBeenCalledWith({
        type: 'runner_assigned',
        recipientUserId: 'student-1',
        title: 'Runner assigned',
        body: `${runnerDisplayName('Tobi Adeyemi')} is picking up your order from Golden Crust Bakery.`,
        data: { orderId: claimedOrder.id },
      });
      expect(notifications.emit).toHaveBeenCalledTimes(2);
    });

    it('sends nothing when the claim is lost to another runner', async () => {
      const { service, prisma, notifications } = makeService();
      winClaim(prisma);
      prisma.orderEscrow.updateMany.mockResolvedValue({ count: 0 });

      await expect(service.claim(claimedOrder.id, runner)).rejects.toThrow(ConflictException);
      expect(notifications.emit).not.toHaveBeenCalled();
    });

    it("sends nothing again for the same runner's retried claim", async () => {
      const { service, prisma, notifications } = makeService();
      approveKyc(prisma);
      prisma.orderEscrow.findUnique.mockResolvedValue({ ...unclaimedEscrow, runnerUserId: 'runner-1' });

      await service.claim(claimedOrder.id, runner);
      expect(notifications.emit).not.toHaveBeenCalled();
    });

    it('still sends sensible copy if the names are missing', async () => {
      const { service, prisma, notifications } = makeService();
      winClaim(prisma);
      prisma.vendor.findUnique.mockResolvedValue(null);
      prisma.user.findUnique.mockResolvedValue({ name: null });

      await service.claim(claimedOrder.id, runner);

      expect(notifications.emit).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'runner_assigned', body: `${runnerDisplayName(null)} is picking up your order from the restaurant.` }),
      );
    });
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
      expect.objectContaining({
        amountKobo: 7_000,
        recipientCode: 'RCP_restaurant',
        reference: 'escrow_esc1_restaurant',
        // Shows on the restaurant's bank statement.
        reason: 'Bridgit order order-1 — restaurant payout',
      }),
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

  it('Task 47: cancels a Pay on Delivery order with no wallet transaction to credit back — no wallet lookup at all', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow, studentWalletTransactionId: null });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    prisma.orderEscrow.findUniqueOrThrow.mockResolvedValue({
      ...heldEscrow,
      studentWalletTransactionId: null,
      status: 'refunded',
    });

    const result = await service.refund('order-1');

    expect(prisma.walletTransaction.findUniqueOrThrow).not.toHaveBeenCalled();
    expect(prisma.wallet.update).not.toHaveBeenCalled();
    expect(prisma.walletTransaction.create).not.toHaveBeenCalled();
    expect(result.status).toBe('refunded');
    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { id: 'order-1' },
      data: { status: 'cancelled', cancelledAt: expect.any(Date) },
    });
  });

  it('Task 61: a required order status + extra order fields are applied in the same order write', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.walletTransaction.findUniqueOrThrow.mockResolvedValue({ id: 'wt1', walletId: 'w1' });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    prisma.order.updateMany.mockResolvedValue({ count: 1 });
    prisma.orderEscrow.findUniqueOrThrow.mockResolvedValue({ ...heldEscrow, status: 'refunded' });

    await service.refund('order-1', { requireOrderStatus: 'placed', orderData: { declineReason: 'too_busy' } });

    expect(prisma.order.updateMany).toHaveBeenCalledWith({
      where: { id: 'order-1', status: 'placed' },
      data: { declineReason: 'too_busy', status: 'cancelled', cancelledAt: expect.any(Date) },
    });
  });

  it('Task 61: throws (rolling the whole refund back) when the order is no longer in the required status', async () => {
    const { service, prisma } = makeService();
    prisma.orderEscrow.findUnique.mockResolvedValue({ ...heldEscrow });
    prisma.walletTransaction.findUniqueOrThrow.mockResolvedValue({ id: 'wt1', walletId: 'w1' });
    prisma.orderEscrow.updateMany.mockResolvedValue({ count: 1 });
    // e.g. the restaurant accepted it (placed -> preparing) a moment earlier
    prisma.order.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.refund('order-1', { requireOrderStatus: 'placed' })).rejects.toThrow(ConflictException);
    expect(prisma.orderEscrow.findUniqueOrThrow).not.toHaveBeenCalled();
  });
});
