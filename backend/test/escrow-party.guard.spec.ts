import { ExecutionContext, ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Reflector } from '@nestjs/core';
import { EscrowPartyGuard } from '../src/common/guards/escrow-party.guard';
import { createConfigMock, createPrismaMock } from './support/mocks';

function contextFor(request: any, handler: () => void = () => undefined): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => handler,
  } as unknown as ExecutionContext;
}

describe('EscrowPartyGuard', () => {
  let jwt: { verifyAsync: jest.Mock };
  let prisma: ReturnType<typeof createPrismaMock>;
  let reflector: { get: jest.Mock };
  let guard: EscrowPartyGuard;
  const config = createConfigMock({
    internalServiceApiKey: 'internal-secret',
    'jwt.secret': 'test-secret',
  });

  beforeEach(() => {
    jwt = { verifyAsync: jest.fn() };
    prisma = createPrismaMock();
    reflector = { get: jest.fn() };
    guard = new EscrowPartyGuard(jwt as unknown as JwtService, config as any, prisma, reflector as unknown as Reflector);
  });

  it('allows the internal service key regardless of party', async () => {
    const request: any = { headers: { 'x-internal-api-key': 'internal-secret' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
    expect(request.user).toEqual({ sub: 'internal-service', role: 'internal_service' });
    expect(jwt.verifyAsync).not.toHaveBeenCalled();
  });

  it('allows an admin JWT regardless of which escrow party it is', async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'admin-1', role: 'admin' });
    const request: any = { headers: { authorization: 'Bearer admin-token' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
    expect(prisma.orderEscrow.findUnique).not.toHaveBeenCalled();
  });

  it('rejects with no internal key and no token', async () => {
    const request: any = { headers: {}, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it("allows the assigned runner's own JWT to release their own order's escrow", async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'runner-1', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue({ runnerUserId: 'runner-1', studentWalletTransactionId: 'txn-1' });
    reflector.get.mockReturnValue('runner');
    const request: any = { headers: { authorization: 'Bearer runner-token' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
  });

  it("rejects a different runner's JWT for someone else's order", async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'runner-2', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue({ runnerUserId: 'runner-1', studentWalletTransactionId: 'txn-1' });
    reflector.get.mockReturnValue('runner');
    const request: any = { headers: { authorization: 'Bearer runner-token' }, params: { orderId: 'order-1' } };
    // 403, not 401: a real, valid token — just not authorized for this
    // order — see the guard's own doc comment on why that distinction
    // matters for Task 17's global session-invalidation handling.
    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("allows the ordering student's own JWT to refund their own order's escrow", async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'student-1', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue({ runnerUserId: 'runner-1', studentWalletTransactionId: 'txn-1' });
    prisma.order.findUniqueOrThrow.mockResolvedValue({ studentUserId: 'student-1' });
    reflector.get.mockReturnValue('student');
    const request: any = { headers: { authorization: 'Bearer student-token' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
  });

  it("rejects a different student's JWT for someone else's refund", async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'student-2', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue({ runnerUserId: 'runner-1', studentWalletTransactionId: 'txn-1' });
    prisma.order.findUniqueOrThrow.mockResolvedValue({ studentUserId: 'student-1' });
    reflector.get.mockReturnValue('student');
    const request: any = { headers: { authorization: 'Bearer student-token' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("allows the ordering student's own JWT to refund a Pay on Delivery order with no wallet transaction at all", async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'student-1', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue({ runnerUserId: 'runner-1', studentWalletTransactionId: null });
    prisma.order.findUniqueOrThrow.mockResolvedValue({ studentUserId: 'student-1' });
    reflector.get.mockReturnValue('student');
    const request: any = { headers: { authorization: 'Bearer student-token' }, params: { orderId: 'order-1' } };
    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
  });

  it('rejects when there is no escrow for the given order', async () => {
    jwt.verifyAsync.mockResolvedValue({ sub: 'runner-1', role: 'user' });
    prisma.orderEscrow.findUnique.mockResolvedValue(null);
    const request: any = { headers: { authorization: 'Bearer runner-token' }, params: { orderId: 'missing' } };
    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
