import { UnauthorizedException } from '@nestjs/common';
import { JwtStrategy } from '../src/auth/jwt.strategy';
import { createConfigMock, createPrismaMock } from './support/mocks';

function makeStrategy() {
  const prisma = createPrismaMock();
  const config = createConfigMock({ 'jwt.secret': 'test-secret-at-least-16-chars' });
  const strategy = new JwtStrategy(config as any, prisma as any);
  return { strategy, prisma };
}

describe('JwtStrategy.validate', () => {
  it('allows an active user through unchanged', async () => {
    const { strategy, prisma } = makeStrategy();
    prisma.user.findUnique.mockResolvedValue({ suspendedAt: null });
    const payload = { sub: 'user-1', accountType: 'student' as const, role: 'user' as const };

    await expect(strategy.validate(payload)).resolves.toEqual(payload);
  });

  it('rejects a suspended user even with an otherwise-valid token', async () => {
    const { strategy, prisma } = makeStrategy();
    prisma.user.findUnique.mockResolvedValue({ suspendedAt: new Date() });
    const payload = { sub: 'user-1', accountType: 'student' as const, role: 'user' as const };

    await expect(strategy.validate(payload)).rejects.toThrow(
      new UnauthorizedException('Your session has expired. Please sign in again.'),
    );
  });

  it('rejects a token whose sub no longer maps to any real user', async () => {
    const { strategy, prisma } = makeStrategy();
    prisma.user.findUnique.mockResolvedValue(null);
    const payload = { sub: 'ghost-user', accountType: 'student' as const, role: 'user' as const };

    await expect(strategy.validate(payload)).rejects.toThrow(UnauthorizedException);
  });
});
