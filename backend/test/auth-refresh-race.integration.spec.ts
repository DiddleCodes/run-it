/**
 * Real-Postgres proof of Task 34's rotation guarantee — the same class of
 * race Task 21a's claim-race fix closed for order claims, applied here to
 * a refresh token's revoke-on-use instead: two concurrent /auth/refresh
 * calls against the *same* refresh token must not both succeed. A
 * mocked-Prisma unit test (auth.service.spec.ts) can assert the right
 * WHERE clause was constructed, but only a real database can prove the
 * race is actually closed — see order-escrow.db-constraint's own doc
 * comment for the same reasoning applied to hold()'s duplicate-escrow race.
 *
 * Skipped by default: `npm test` must not require a live database.
 *
 *   RUN_DB_INTEGRATION_TESTS=1 npx jest auth-refresh-race
 */
import { UnauthorizedException } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';
import { randomUUID, createHash } from 'crypto';
import { AuthService } from '../src/auth/auth.service';

const RUN = process.env.RUN_DB_INTEGRATION_TESTS === '1';
const describeIfDb = RUN ? describe : describe.skip;

const sha256 = (raw: string) => createHash('sha256').update(raw).digest('hex');

function makeRealService(prisma: PrismaClient) {
  const jwt = { sign: jest.fn().mockReturnValue('signed.jwt.token') };
  const email = { send: jest.fn() };
  const config = { get: jest.fn() };
  const campus = { resolveByEmail: jest.fn(), requireById: jest.fn(), list: jest.fn() };
  return new AuthService(prisma as any, jwt as any, email as any, config as any, campus as any);
}

describeIfDb('AuthService.refresh — real concurrent reuse of the same refresh token', () => {
  const prisma = new PrismaClient();
  let userId: string;
  let refreshTokenId: string;
  const rawRefreshToken = `t34-raw-${randomUUID()}`;

  beforeAll(async () => {
    userId = randomUUID();
    await prisma.user.create({ data: { id: userId, email: `t34-student-${userId}@test.internal`, accountType: 'student' } });
    const token = await prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: sha256(rawRefreshToken),
        expiresAt: new Date(Date.now() + 1000 * 60 * 60 * 24 * 30),
      },
    });
    refreshTokenId = token.id;
  });

  afterAll(async () => {
    await prisma.refreshToken.deleteMany({ where: { userId } });
    await prisma.user.delete({ where: { id: userId } });
    await prisma.$disconnect();
  });

  it('lets exactly one of two simultaneous refreshes of the same token win, and the loser gets a clean rejection', async () => {
    const service = makeRealService(prisma);

    // Genuinely concurrent — both requests fire before either has a chance
    // to observe the other's result. This is the actual race the refresh
    // token's conditional `updateMany({where: {revokedAt: null}}})` has to
    // close at the database level, not application logic serializing them.
    const [resultA, resultB] = await Promise.allSettled([
      service.refresh(rawRefreshToken),
      service.refresh(rawRefreshToken),
    ]);

    const outcomes = [resultA, resultB];
    const fulfilled = outcomes.filter((r) => r.status === 'fulfilled');
    const rejected = outcomes.filter((r) => r.status === 'rejected');

    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);
    expect((rejected[0] as PromiseRejectedResult).reason).toBeInstanceOf(UnauthorizedException);

    // The database itself agrees: the original token is revoked exactly
    // once, and exactly one brand-new refresh token row exists for this
    // user as a result of the winning call.
    const original = await prisma.refreshToken.findUniqueOrThrow({ where: { id: refreshTokenId } });
    expect(original.revokedAt).not.toBeNull();

    const allTokens = await prisma.refreshToken.findMany({ where: { userId } });
    expect(allTokens).toHaveLength(2); // the original (now revoked) + exactly one new one
    const liveTokens = allTokens.filter((t) => t.revokedAt === null);
    expect(liveTokens).toHaveLength(1);
  });
});
