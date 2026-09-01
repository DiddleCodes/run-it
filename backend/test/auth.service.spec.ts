import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createHash } from 'crypto';
import { AuthService } from '../src/auth/auth.service';
import { createConfigMock, createPrismaMock } from './support/mocks';

// AuthService.hashToken is private — mirrors it exactly so a test can
// build a stored otpVerification/passwordResetToken fixture the service's
// own hash comparison will actually match.
const sha256 = (raw: string) => createHash('sha256').update(raw).digest('hex');

function makeService(configValues: Record<string, unknown> = { nodeEnv: 'test' }) {
  const prisma = createPrismaMock();
  const jwt = { sign: jest.fn().mockReturnValue('signed.jwt.token') };
  const email = { send: jest.fn().mockResolvedValue(true) };
  const config = createConfigMock(configValues);
  const service = new AuthService(prisma as any, jwt as any, email as any, config as any);
  return { service, prisma, jwt, email, config };
}

describe('AuthService.login', () => {
  it('rejects when no user has that email', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.login('nobody@runit.dev', 'whatever')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects a user with no password set (mobile-only student/runner accounts)', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'student', password: null });

    await expect(service.login('student@runit.dev', 'whatever')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects the wrong password', async () => {
    const { service, prisma } = makeService();
    const hash = await bcrypt.hash('correct-password', 4);
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant', password: hash });

    await expect(service.login('r@runit.dev', 'wrong-password')).rejects.toThrow(UnauthorizedException);
  });

  it('signs a JWT with role=admin for admin accounts and role=user for restaurant accounts', async () => {
    const { service, prisma, jwt } = makeService();
    const hash = await bcrypt.hash('correct-password', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'admin-1',
      email: 'admin@runit.dev',
      name: 'Admin',
      accountType: 'admin',
      password: hash,
    });

    const result = await service.login('admin@runit.dev', 'correct-password');

    expect(jwt.sign).toHaveBeenCalledWith({ sub: 'admin-1', accountType: 'admin', role: 'admin' });
    expect(result.accessToken).toBe('signed.jwt.token');
    expect(result.user).toEqual({ id: 'admin-1', email: 'admin@runit.dev', name: 'Admin', accountType: 'admin' });
  });

  it('signs role=user (not admin) for a restaurant account', async () => {
    const { service, prisma, jwt } = makeService();
    const hash = await bcrypt.hash('correct-password', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'r1',
      email: 'r@runit.dev',
      name: 'Restaurant',
      accountType: 'restaurant',
      password: hash,
    });

    await service.login('r@runit.dev', 'correct-password');

    expect(jwt.sign).toHaveBeenCalledWith({ sub: 'r1', accountType: 'restaurant', role: 'user' });
  });

  it('rejects a suspended account even with the correct password, using the same generic message', async () => {
    const { service, prisma, jwt } = makeService();
    const hash = await bcrypt.hash('correct-password', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'r1',
      email: 'r@runit.dev',
      accountType: 'restaurant',
      password: hash,
      suspendedAt: new Date(),
    });

    await expect(service.login('r@runit.dev', 'correct-password')).rejects.toThrow(
      new UnauthorizedException('Invalid email or password'),
    );
    expect(jwt.sign).not.toHaveBeenCalled();
  });

  it('allows a reinstated account (suspendedAt null) to log in normally', async () => {
    const { service, prisma } = makeService();
    const hash = await bcrypt.hash('correct-password', 4);
    prisma.user.findUnique.mockResolvedValue({
      id: 'r1',
      email: 'r@runit.dev',
      name: 'Restaurant',
      accountType: 'restaurant',
      password: hash,
      suspendedAt: null,
    });

    await expect(service.login('r@runit.dev', 'correct-password')).resolves.toBeDefined();
  });
});

describe('AuthService.requestPasswordReset', () => {
  it('returns the same generic message whether or not the email is registered', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);
    const notFoundResult = await service.requestPasswordReset('nobody@runit.dev');

    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant' });
    prisma.passwordResetToken.create.mockResolvedValue({});
    const foundResult = await service.requestPasswordReset('r@runit.dev');

    expect(notFoundResult).toEqual(foundResult);
  });

  it('never creates a reset token for a student/runner account (no password login for them)', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'student' });

    await service.requestPasswordReset('student@runit.dev');

    expect(prisma.passwordResetToken.create).not.toHaveBeenCalled();
  });

  it('creates a hashed, expiring token for a valid restaurant/admin account', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'admin' });
    prisma.passwordResetToken.create.mockResolvedValue({});

    await service.requestPasswordReset('admin@runit.dev');

    expect(prisma.passwordResetToken.create).toHaveBeenCalledTimes(1);
    const { data } = prisma.passwordResetToken.create.mock.calls[0][0];
    expect(data.userId).toBe('u1');
    expect(data.tokenHash).toMatch(/^[a-f0-9]{64}$/); // sha256 hex digest, never the raw token
    expect(data.expiresAt.getTime()).toBeGreaterThan(Date.now());
  });
});

describe('AuthService.resetPassword', () => {
  it('rejects an unknown token', async () => {
    const { service, prisma } = makeService();
    prisma.passwordResetToken.findUnique.mockResolvedValue(null);

    await expect(service.resetPassword('bogus-token', 'NewPassword123!')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects an already-used token', async () => {
    const { service, prisma } = makeService();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u1',
      usedAt: new Date(),
      expiresAt: new Date(Date.now() + 60_000),
    });

    await expect(service.resetPassword('used-token', 'NewPassword123!')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects an expired token', async () => {
    const { service, prisma } = makeService();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u1',
      usedAt: null,
      expiresAt: new Date(Date.now() - 1000),
    });

    await expect(service.resetPassword('expired-token', 'NewPassword123!')).rejects.toThrow(UnauthorizedException);
  });

  it('updates the password and marks the token used, atomically', async () => {
    const { service, prisma } = makeService();
    prisma.passwordResetToken.findUnique.mockResolvedValue({
      id: 't1',
      userId: 'u1',
      usedAt: null,
      expiresAt: new Date(Date.now() + 60_000),
    });
    prisma.user.update.mockResolvedValue({});
    prisma.passwordResetToken.update.mockResolvedValue({});

    await service.resetPassword('valid-token', 'NewPassword123!');

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'u1' } }),
    );
    expect(prisma.passwordResetToken.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 't1' }, data: { usedAt: expect.any(Date) } }),
    );
  });
});

describe('AuthService.requestOtp', () => {
  it('deletes any live code for the contact and creates a fresh one, expiring in the future', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 1 });
    prisma.otpVerification.create.mockResolvedValue({});

    const result = await service.requestOtp('student@runit.dev', 'student');

    expect(prisma.otpVerification.deleteMany).toHaveBeenCalledWith({
      where: { contact: 'student@runit.dev', consumedAt: null },
    });
    expect(prisma.otpVerification.create).toHaveBeenCalledTimes(1);
    const { data } = prisma.otpVerification.create.mock.calls[0][0];
    expect(data.contact).toBe('student@runit.dev');
    expect(data.codeHash).toMatch(/^[a-f0-9]{64}$/); // sha256 hex digest, never the raw code
    expect(data.expiresAt.getTime()).toBeGreaterThan(Date.now());
    expect(result).toEqual({ message: 'If this contact is valid, a verification code has been sent.' });
  });

  // Task 20: student contacts are always an email — real delivery via
  // EmailService (Brevo), never the plaintext log.
  it('sends a student OTP via EmailService, never logging the code, when EmailService succeeds', async () => {
    const { service, prisma, email } = makeService();
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    const logSpy = jest.spyOn((service as any).logger, 'warn');
    const logLogSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestOtp('student@runit.dev', 'student');

    expect(email.send).toHaveBeenCalledTimes(1);
    const emailArgs = email.send.mock.calls[0][0];
    expect(emailArgs.to).toBe('student@runit.dev');
    expect(emailArgs.html).not.toContain('undefined');
    expect(logSpy).not.toHaveBeenCalled();
    expect(logLogSpy).not.toHaveBeenCalled();
  });

  it('falls back to a dev-only log when EmailService fails outside production', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'development' });
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');

    await service.requestOtp('student@runit.dev', 'student');

    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain('[DEV ONLY]');
  });

  it('never logs the code when EmailService fails in production — only a warning with no code in it', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'production' });
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');
    const logSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestOtp('student@runit.dev', 'student');

    expect(warnSpy).not.toHaveBeenCalled();
    expect(logSpy).not.toHaveBeenCalled();
  });

  // Task 20: runner contacts are always a phone number — no delivery
  // channel exists yet (SMS out of scope), so this deliberately keeps
  // logging in every environment, exactly as it did before this task.
  it('never calls EmailService for a runner contact and keeps logging the code, even in production', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'production' });
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    const logSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestOtp('+2348000000000', 'runner');

    expect(email.send).not.toHaveBeenCalled();
    expect(logSpy).toHaveBeenCalledTimes(1);
    expect(logSpy.mock.calls[0][0]).toContain('+2348000000000');
  });
});

describe('AuthService.verifyOtp', () => {
  it('rejects when no live code exists for the contact', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue(null);

    await expect(service.verifyOtp('student@runit.dev', '123456', 'student')).rejects.toThrow(
      new UnauthorizedException('Invalid or expired code'),
    );
  });

  it('rejects the wrong code even when a live one exists for the contact', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-1', codeHash: sha256('654321') });

    await expect(service.verifyOtp('student@runit.dev', '123456', 'student')).rejects.toThrow(
      new UnauthorizedException('Invalid or expired code'),
    );
    expect(prisma.otpVerification.update).not.toHaveBeenCalled();
  });

  it('consumes the code, creates a new User + Wallet on first verify, and signs a session', async () => {
    const { service, prisma, jwt } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-1', codeHash: sha256('123456') });
    prisma.user.findUnique.mockResolvedValue(null); // no existing account for this contact
    prisma.user.create.mockResolvedValue({
      id: 'student-1',
      email: 'student@runit.dev',
      name: 'Ada',
      accountType: 'student',
      suspendedAt: null,
    });
    prisma.wallet.create.mockResolvedValue({});

    const result = await service.verifyOtp('student@runit.dev', '123456', 'student', 'Ada');

    expect(prisma.otpVerification.update).toHaveBeenCalledWith({
      where: { id: 'otp-1' },
      data: { consumedAt: expect.any(Date) },
    });
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: { email: 'student@runit.dev', accountType: 'student', name: 'Ada' },
    });
    expect(prisma.wallet.create).toHaveBeenCalledWith({ data: { userId: 'student-1', balance: 0 } });
    expect(jwt.sign).toHaveBeenCalledWith({ sub: 'student-1', accountType: 'student', role: 'user' });
    expect(result.accessToken).toBe('signed.jwt.token');
  });

  it('finds the existing User on a repeat verify — never creates a duplicate account or wallet', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-2', codeHash: sha256('111222') });
    prisma.user.findUnique.mockResolvedValue({
      id: 'runner-1',
      phone: '+2348000000000',
      accountType: 'runner',
      suspendedAt: null,
    });

    await service.verifyOtp('+2348000000000', '111222', 'runner');

    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(prisma.wallet.create).not.toHaveBeenCalled();
  });

  it('looks up by phone (not email) for a runner account', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-3', codeHash: sha256('999999') });
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', accountType: 'runner', suspendedAt: null });

    await service.verifyOtp('+2348000000000', '999999', 'runner');

    expect(prisma.user.findUnique).toHaveBeenCalledWith({ where: { phone: '+2348000000000' } });
  });

  it('rejects a suspended account with the same generic message as a wrong code, even with the correct code', async () => {
    const { service, prisma, jwt } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-4', codeHash: sha256('555555') });
    prisma.user.findUnique.mockResolvedValue({
      id: 'student-1',
      email: 'student@runit.dev',
      accountType: 'student',
      suspendedAt: new Date(),
    });

    await expect(service.verifyOtp('student@runit.dev', '555555', 'student')).rejects.toThrow(
      new UnauthorizedException('Invalid or expired code'),
    );
    expect(jwt.sign).not.toHaveBeenCalled();
  });

  it('never accepts the same code twice (consumed codes are excluded from the live lookup query)', async () => {
    const { service, prisma } = makeService();
    // findFirst is scoped to consumedAt: null — a replayed code simply
    // won't be found once consumed, exercised here via the query itself.
    prisma.otpVerification.findFirst.mockResolvedValue(null);

    await expect(service.verifyOtp('student@runit.dev', '123456', 'student')).rejects.toThrow(UnauthorizedException);
    expect(prisma.otpVerification.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({ where: expect.objectContaining({ consumedAt: null }) }),
    );
  });
});
