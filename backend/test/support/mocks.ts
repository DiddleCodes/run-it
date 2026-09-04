export function createPrismaMock() {
  const prisma: any = {
    user: {
      findUnique: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      update: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
    },
    passwordResetToken: {
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
    },
    refreshToken: {
      findUnique: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    otpVerification: {
      findFirst: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      deleteMany: jest.fn(),
    },
    wallet: {
      findUnique: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      create: jest.fn(),
    },
    walletTransaction: {
      create: jest.fn(),
      findUnique: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      updateMany: jest.fn(),
      findMany: jest.fn(),
    },
    orderEscrow: {
      findUnique: jest.fn(),
      findFirst: jest.fn(),
      findMany: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      aggregate: jest.fn().mockResolvedValue({ _sum: { platformFee: 0 } }),
    },
    payoutAccount: {
      findUnique: jest.fn(),
      upsert: jest.fn(),
    },
    vendor: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      upsert: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
    },
    runnerKyc: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      update: jest.fn(),
      upsert: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
    },
    adminAuditLog: {
      create: jest.fn(),
    },
    reconciliationRun: {
      create: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
    },
    reconciliationResolution: {
      findMany: jest.fn().mockResolvedValue([]),
      upsert: jest.fn(),
    },
    dispute: {
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      create: jest.fn(),
      update: jest.fn(),
      upsert: jest.fn(),
    },
    vendorCategory: {
      findMany: jest.fn().mockResolvedValue([]),
    },
    menuItem: {
      findUnique: jest.fn(),
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn(),
    },
    order: {
      findUnique: jest.fn(),
      findUniqueOrThrow: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      upsert: jest.fn(),
      update: jest.fn(),
      updateMany: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
      aggregate: jest.fn().mockResolvedValue({ _sum: { totalAmount: 0 } }),
      groupBy: jest.fn().mockResolvedValue([]),
    },
    orderItem: {
      createMany: jest.fn(),
    },
    runnerRating: {
      findUnique: jest.fn(),
      create: jest.fn(),
      aggregate: jest.fn(),
    },
    notification: {
      create: jest.fn(),
      findUnique: jest.fn(),
      findMany: jest.fn().mockResolvedValue([]),
      update: jest.fn(),
      count: jest.fn().mockResolvedValue(0),
    },
    deviceToken: {
      upsert: jest.fn(),
      deleteMany: jest.fn(),
      delete: jest.fn().mockResolvedValue(undefined),
      findMany: jest.fn().mockResolvedValue([]),
    },
    $transaction: jest.fn(async (arg: any) => (typeof arg === 'function' ? arg(prisma) : Promise.all(arg))),
  };
  return prisma;
}

export function createPaystackMock() {
  return {
    verifyWebhookSignature: jest.fn(),
    initializeTransaction: jest.fn(),
    resolveAccount: jest.fn(),
    createTransferRecipient: jest.fn(),
    initiateTransfer: jest.fn(),
    verifyTransaction: jest.fn(),
    verifyTransferStatus: jest.fn(),
    listTransactions: jest.fn().mockResolvedValue({ items: [], page: 1, pageCount: 1 }),
    listTransfers: jest.fn().mockResolvedValue({ items: [], page: 1, pageCount: 1 }),
  };
}

export function createRedisMock() {
  return {
    wasAlreadyProcessed: jest.fn().mockResolvedValue(false),
    markProcessed: jest.fn().mockResolvedValue(undefined),
    // Task 11: OrdersService's per-order verification-attempt rate limiter
    // uses these raw ioredis methods directly (RedisService extends Redis).
    get: jest.fn().mockResolvedValue(null),
    incr: jest.fn().mockResolvedValue(1),
    expire: jest.fn().mockResolvedValue(1),
    del: jest.fn().mockResolvedValue(1),
  };
}

export function createConfigMock(values: Record<string, unknown>) {
  return {
    get: jest.fn((key: string) => values[key]),
  };
}

// Task 19a: NotificationsEmitterService.emit is fire-and-forget (see its
// own doc comment) — every trigger-point service just needs something to
// call it on, not a real EventEmitter2 wired up in these unit tests.
export function createNotificationsEmitterMock() {
  return {
    emit: jest.fn(),
  };
}

// Task 21a: MatchingService's actual queue/gateway/Prisma wiring is
// exercised in matching.service.spec.ts itself — every other consumer
// (OrderEscrowService.claim, VendorsService.advanceOrderStatus) only needs
// something to call these two methods on.
export function createMatchingServiceMock() {
  return {
    broadcastNewJob: jest.fn().mockResolvedValue(undefined),
    cancelPendingJobs: jest.fn().mockResolvedValue(undefined),
  };
}

// Task 31: AlertsService.send is deliberately never-throwing in the real
// implementation too — this mock mirrors that rather than needing every
// caller test to await/handle it.
export function createAlertsMock() {
  return {
    send: jest.fn().mockResolvedValue(undefined),
  };
}

// Task 32: WalletService.initiateWithdrawal calls back into
// WebhooksService.applyVerifiedTransferResult for the synchronous-failure
// reversal — same shared idempotent path a delayed webhook/reconciliation
// call uses (see that method's own doc comment) — so callers just need
// something to call it on, not the real DB-mutating implementation.
export function createWebhooksServiceMock() {
  return {
    applyVerifiedChargeSuccess: jest.fn().mockResolvedValue(undefined),
    markChargeFailed: jest.fn().mockResolvedValue(undefined),
    applyVerifiedTransferResult: jest.fn().mockResolvedValue(undefined),
  };
}
