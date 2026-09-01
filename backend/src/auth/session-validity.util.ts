import { UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

// Deliberately generic — an ongoing request's rejection never says
// "suspended" any more than a fresh login's does (see AuthService.login's
// own doc comment on why). A genuinely expired JWT reads the same way to
// the user regardless of cause, so one honest, actionable message covers
// both.
export const SESSION_INVALID_MESSAGE = 'Your session has expired. Please sign in again.';

/**
 * Task 17: the per-request half of suspension enforcement. Login-time
 * checks (AuthService.login, AuthService.verifyOtp) only block the *next*
 * sign-in — they do nothing about a token minted before an admin suspended
 * the account. This closes that gap: called from JwtStrategy.validate()
 * (every JwtAuthGuard-protected route) and AdminGuard, it's the single
 * place that makes an already-issued token stop working the moment the
 * account is suspended, not just when it naturally expires.
 */
export async function assertUserNotSuspended(prisma: PrismaService, userId: string): Promise<void> {
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { suspendedAt: true } });
  if (!user || user.suspendedAt) {
    throw new UnauthorizedException(SESSION_INVALID_MESSAGE);
  }
}
