import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { AdminGuard } from '../src/common/guards/admin.guard';
import { createConfigMock, createPrismaMock } from './support/mocks';

function contextFor(request: any): ExecutionContext {
  return { switchToHttp: () => ({ getRequest: () => request }) } as unknown as ExecutionContext;
}

function makeGuard() {
  const jwt = { verifyAsync: jest.fn() };
  const prisma = createPrismaMock();
  const config = createConfigMock({ 'jwt.secret': 'test-secret' });
  const guard = new AdminGuard(jwt as unknown as JwtService, config as any, prisma as any);
  return { guard, jwt, prisma };
}

describe('AdminGuard', () => {
  it('rejects when no token is presented', async () => {
    const { guard } = makeGuard();
    const request: any = { headers: {} };

    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a non-admin-role token', async () => {
    const { guard, jwt } = makeGuard();
    jwt.verifyAsync.mockResolvedValue({ sub: 'user-1', role: 'user' });
    const request: any = { headers: { authorization: 'Bearer token' } };

    await expect(guard.canActivate(contextFor(request))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('allows an active admin', async () => {
    const { guard, jwt, prisma } = makeGuard();
    jwt.verifyAsync.mockResolvedValue({ sub: 'admin-1', role: 'admin' });
    prisma.user.findUnique.mockResolvedValue({ suspendedAt: null });
    const request: any = { headers: { authorization: 'Bearer admin-token' } };

    await expect(guard.canActivate(contextFor(request))).resolves.toBe(true);
    expect(request.user).toEqual({ sub: 'admin-1', role: 'admin' });
  });

  // Task 17: an admin's own account being suspended must lock them out of
  // /admin/* immediately too, not just block their next login — this guard
  // verifies the token itself rather than going through JwtStrategy, so it
  // needs its own per-request check.
  it("rejects an admin whose account has since been suspended, even with a valid, unexpired token", async () => {
    const { guard, jwt, prisma } = makeGuard();
    jwt.verifyAsync.mockResolvedValue({ sub: 'admin-1', role: 'admin' });
    prisma.user.findUnique.mockResolvedValue({ suspendedAt: new Date() });
    const request: any = { headers: { authorization: 'Bearer admin-token' } };

    await expect(guard.canActivate(contextFor(request))).rejects.toThrow(
      new UnauthorizedException('Your session has expired. Please sign in again.'),
    );
  });
});
