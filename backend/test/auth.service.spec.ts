import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { createHash } from 'crypto';
import { AuthService } from '../src/auth/auth.service';
import { createConfigMock, createPrismaMock } from './support/mocks';

// AuthService.hashToken is private — mirrors it exactly so a test can
// build a stored otpVerification/passwordResetToken fixture the service's
// own hash comparison will actually match.
const sha256 = (raw: string) => createHash('sha256').update(raw).digest('hex');

// Every fixture contact in this file uses the `runit.dev` domain — mocked
// here to always resolve to one campus, so requestOtp/verifyOtp's Task 26
// domain check never blocks a pre-existing test that has nothing to do
// with campus enforcement itself (that gets its own dedicated tests below).
function makeService(configValues: Record<string, unknown> = { nodeEnv: 'test' }) {
  const prisma = createPrismaMock();
  const jwt = { sign: jest.fn().mockReturnValue('signed.jwt.token') };
  const email = { send: jest.fn().mockResolvedValue(true) };
  const config = createConfigMock(configValues);
  const campus = {
    resolveByEmail: jest.fn().mockResolvedValue({ id: 'campus-1', name: 'Test Campus', allowedEmailDomains: ['runit.dev'] }),
    requireById: jest.fn(),
    list: jest.fn(),
  };
  const service = new AuthService(prisma as any, jwt as any, email as any, config as any, campus as any);
  return { service, prisma, jwt, email, config, campus };
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

  // Task 36: the reset link used to only ever be logged server-side —
  // now it's actually emailed via the same real Brevo path requestOtp uses.
  it('emails the reset link via EmailService, built from the configured dashboard URL', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'test', dashboardUrl: 'https://dashboard.runit.app' });
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'admin' });
    prisma.passwordResetToken.create.mockResolvedValue({});

    await service.requestPasswordReset('admin@runit.dev');

    expect(email.send).toHaveBeenCalledTimes(1);
    const emailArgs = email.send.mock.calls[0][0];
    expect(emailArgs.to).toBe('admin@runit.dev');
    expect(emailArgs.html).toContain('https://dashboard.runit.app/reset-password?token=');
    expect(emailArgs.text).toContain('https://dashboard.runit.app/reset-password?token=');
  });

  it('never calls EmailService for an unregistered email or a student/runner account', async () => {
    const { service, prisma, email } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);
    await service.requestPasswordReset('nobody@runit.dev');
    expect(email.send).not.toHaveBeenCalled();

    prisma.user.findUnique.mockResolvedValue({ id: 'u2', accountType: 'student' });
    await service.requestPasswordReset('student@runit.dev');
    expect(email.send).not.toHaveBeenCalled();
  });

  it('falls back to a dev-only log (with the link, not the raw request) when EmailService fails outside production', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'development', dashboardUrl: 'http://localhost:3001' });
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant' });
    prisma.passwordResetToken.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');

    await service.requestPasswordReset('r@runit.dev');

    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain('[DEV ONLY]');
    expect(warnSpy.mock.calls[0][0]).toContain('http://localhost:3001/reset-password?token=');
  });

  it('never logs the reset link in production when EmailService fails — only silence, matching requestOtp', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'production' });
    prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant' });
    prisma.passwordResetToken.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');
    const logSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestPasswordReset('r@runit.dev');

    expect(warnSpy).not.toHaveBeenCalled();
    expect(logSpy).not.toHaveBeenCalled();
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

  // Task 28: runner contacts are an email now too — same real Brevo
  // delivery path as students, and the old unconditional plaintext log
  // for runners is gone entirely.
  it('sends a runner OTP via EmailService, never logging the code, when EmailService succeeds', async () => {
    const { service, prisma, email } = makeService();
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    const logSpy = jest.spyOn((service as any).logger, 'warn');
    const logLogSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestOtp('runner@runit.dev', 'runner');

    expect(email.send).toHaveBeenCalledTimes(1);
    expect(email.send.mock.calls[0][0].to).toBe('runner@runit.dev');
    expect(logSpy).not.toHaveBeenCalled();
    expect(logLogSpy).not.toHaveBeenCalled();
  });

  it('never logs the code for a runner in production either — same as students, only a warning with no code in it', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'production' });
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');
    const logSpy = jest.spyOn((service as any).logger, 'log');

    await service.requestOtp('runner@runit.dev', 'runner');

    expect(warnSpy).not.toHaveBeenCalled();
    expect(logSpy).not.toHaveBeenCalled();
  });

  it('falls back to a dev-only log for a runner too when EmailService fails outside production', async () => {
    const { service, prisma, email } = makeService({ nodeEnv: 'development' });
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});
    email.send.mockResolvedValue(false);
    const warnSpy = jest.spyOn((service as any).logger, 'warn');

    await service.requestOtp('runner@runit.dev', 'runner');

    expect(warnSpy).toHaveBeenCalledTimes(1);
    expect(warnSpy.mock.calls[0][0]).toContain('[DEV ONLY]');
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
      data: { email: 'student@runit.dev', accountType: 'student', name: 'Ada', campusId: 'campus-1' },
    });
    expect(prisma.wallet.create).toHaveBeenCalledWith({ data: { userId: 'student-1', balance: 0 } });
    // Task 34: the mobile OTP flow's access token is short-lived (1h) now,
    // unlike login()'s (the dashboard's own, untouched module-default).
    expect(jwt.sign).toHaveBeenCalledWith(
      { sub: 'student-1', accountType: 'student', role: 'user' },
      { expiresIn: '1h' },
    );
    expect(result.accessToken).toBe('signed.jwt.token');
    // Task 34: a real refresh token, hashed and persisted server-side —
    // never the access token itself, and never returned in plaintext form
    // anywhere but this one response.
    expect(typeof result.refreshToken).toBe('string');
    expect(result.refreshToken.length).toBeGreaterThan(20);
    expect(prisma.refreshToken.create).toHaveBeenCalledWith({
      data: {
        userId: 'student-1',
        tokenHash: sha256(result.refreshToken),
        expiresAt: expect.any(Date),
      },
    });
  });

  it('finds the existing User on a repeat verify — never creates a duplicate account or wallet', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-2', codeHash: sha256('111222') });
    prisma.user.findUnique.mockResolvedValue({
      id: 'runner-1',
      email: 'runner@runit.dev',
      phone: '+2348000000000',
      accountType: 'runner',
      suspendedAt: null,
    });

    await service.verifyOtp('runner@runit.dev', '111222', 'runner');

    expect(prisma.user.create).not.toHaveBeenCalled();
    expect(prisma.wallet.create).not.toHaveBeenCalled();
  });

  // Task 28: runner accounts are looked up by email now too — the old
  // phone-keyed lookup is gone along with the phone-based OTP path.
  it('looks up by email for a runner account, same as a student', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-3', codeHash: sha256('999999') });
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', accountType: 'runner', suspendedAt: null });

    await service.verifyOtp('runner@runit.dev', '999999', 'runner');

    expect(prisma.user.findUnique).toHaveBeenCalledWith({ where: { email: 'runner@runit.dev' } });
  });

  // Task 28: phone is still collected at runner signup (admin dispute
  // contact — see AuthService.verifyOtp's own doc comment) even though
  // it's no longer the OTP contact itself.
  it('creates a new runner account with both the email contact and the separately-submitted phone, and provisions a Wallet', async () => {
    const { service, prisma } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-3b', codeHash: sha256('888777') });
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({
      id: 'runner-3',
      email: 'runner@runit.dev',
      phone: '+2348000000000',
      accountType: 'runner',
      suspendedAt: null,
    });
    prisma.wallet.create.mockResolvedValue({});

    await service.verifyOtp('runner@runit.dev', '888777', 'runner', 'Femi', '+2348000000000');

    expect(prisma.user.create).toHaveBeenCalledWith({
      data: {
        email: 'runner@runit.dev',
        phone: '+2348000000000',
        accountType: 'runner',
        name: 'Femi',
        campusId: null,
      },
    });
    // Task 33: runners get a wallet at signup now too — delivery earnings
    // land there via OrderEscrowService.release()'s runner leg instead of
    // a direct Paystack transfer.
    expect(prisma.wallet.create).toHaveBeenCalledWith({ data: { userId: 'runner-3', balance: 0 } });
  });

  // Task 33: restaurant payout is deliberately unchanged — still direct to
  // bank on delivery, never through a wallet. Not exercised via verifyOtp
  // at all: AuthService's OTP path only ever accepts 'student' | 'runner'
  // (see OtpAccountType) — a restaurant account is created through the
  // vendor-application flow instead, which never touches wallet.create.
  // The real regression risk this task cares about — release()'s
  // restaurant leg still going out via Paystack, untouched — is covered
  // in order-escrow.service.spec.ts instead.

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

// Task 26: the actual enforcement mechanism — an unrecognized school email
// domain must reject signup, cleanly and honestly, before anything else
// happens.
describe('AuthService campus enforcement (Task 26)', () => {
  it('requestOtp rejects a student whose email domain matches no campus, before creating any OTP row or sending any email', async () => {
    const { service, prisma, email, campus } = makeService();
    campus.resolveByEmail.mockRejectedValue(new Error('no match'));

    await expect(service.requestOtp('student@unknown-school.edu', 'student')).rejects.toThrow();

    expect(prisma.otpVerification.create).not.toHaveBeenCalled();
    expect(email.send).not.toHaveBeenCalled();
  });

  // Task 28: a runner contact is an email now too (not a phone number),
  // but campus enforcement stays student-only regardless — this must
  // never start checking a runner's email domain just because it looks
  // like one.
  it('requestOtp never checks campus for a runner contact, even though it is an email now', async () => {
    const { service, prisma, campus } = makeService();
    prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
    prisma.otpVerification.create.mockResolvedValue({});

    await service.requestOtp('runner@runit.dev', 'runner');

    expect(campus.resolveByEmail).not.toHaveBeenCalled();
  });

  it('verifyOtp rejects creating a student account whose email domain matches no campus', async () => {
    const { service, prisma, campus } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-5', codeHash: sha256('123456') });
    prisma.user.findUnique.mockResolvedValue(null);
    campus.resolveByEmail.mockRejectedValue(new Error('no match'));

    await expect(service.verifyOtp('student@unknown-school.edu', '123456', 'student')).rejects.toThrow();
    expect(prisma.user.create).not.toHaveBeenCalled();
  });

  it('verifyOtp never assigns a campus for a new runner account (admin-assigned, not derived)', async () => {
    const { service, prisma, campus } = makeService();
    prisma.otpVerification.findFirst.mockResolvedValue({ id: 'otp-6', codeHash: sha256('654321') });
    prisma.user.findUnique.mockResolvedValue(null);
    prisma.user.create.mockResolvedValue({ id: 'runner-2', email: 'runner2@runit.dev', accountType: 'runner' });

    await service.verifyOtp('runner2@runit.dev', '654321', 'runner');

    expect(campus.resolveByEmail).not.toHaveBeenCalled();
    expect(prisma.user.create).toHaveBeenCalledWith({
      data: { email: 'runner2@runit.dev', phone: undefined, accountType: 'runner', name: undefined, campusId: null },
    });
  });
});

// Task 29: also the Flutter app's real profile-refresh call — see
// AuthController.refreshProfile/KycStatusScreen's polling.
describe('AuthService.me', () => {
  it("a runner with no RunnerKyc row yet gets a null kycStatus, not an error", async () => {
    const { service, prisma } = makeService();
    prisma.user.findUniqueOrThrow.mockResolvedValue({
      id: 'runner-1',
      email: 'runner1@runit.dev',
      name: 'Runner One',
      accountType: 'runner',
      runnerKyc: null,
    });

    const result = await service.me('runner-1');

    expect(result.kycStatus).toBeNull();
    expect(result.kycRejectionReason).toBeNull();
    expect(result.runnerType).toBeNull();
  });

  it('surfaces the real RunnerKyc row (status, rejection reason, declared vehicle) when one exists', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUniqueOrThrow.mockResolvedValue({
      id: 'runner-1',
      email: 'runner1@runit.dev',
      name: 'Runner One',
      accountType: 'runner',
      runnerKyc: {
        status: 'rejected',
        rejectionReason: 'ID photo was blurry',
        runnerType: 'independent_rider',
        vehicleType: 'motorbike',
        vehiclePlate: 'ABC-123-XY',
      },
    });

    const result = await service.me('runner-1');

    expect(result.kycStatus).toBe('rejected');
    expect(result.kycRejectionReason).toBe('ID photo was blurry');
    expect(result.runnerType).toBe('independent_rider');
    expect(result.vehicleType).toBe('motorbike');
    expect(result.vehiclePlate).toBe('ABC-123-XY');
  });

  it('a student (no runnerKyc relation ever populated) gets a null kycStatus', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUniqueOrThrow.mockResolvedValue({
      id: 'student-1',
      email: 'student1@runit.dev',
      name: 'Student One',
      accountType: 'student',
      runnerKyc: null,
    });

    const result = await service.me('student-1');

    expect(result.kycStatus).toBeNull();
  });
});

// Task 34: real, revocable, rotating refresh tokens for the mobile OTP
// flow — see AuthService.refresh/logout/issueRefreshToken's own doc
// comments for the full rationale.
describe('AuthService.refresh', () => {
  it('rejects an unknown refresh token', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue(null);

    await expect(service.refresh('bogus-token')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects an already-revoked refresh token (replay/reuse after rotation)', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue({
      id: 'rt1',
      userId: 'student-1',
      revokedAt: new Date(),
      expiresAt: new Date(Date.now() + 1000 * 60 * 60),
    });

    await expect(service.refresh('used-already')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects an expired refresh token', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue({
      id: 'rt1',
      userId: 'student-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() - 1000),
    });

    await expect(service.refresh('too-old')).rejects.toThrow(UnauthorizedException);
  });

  it('rejects when the owning user has been suspended since the token was issued', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue({
      id: 'rt1',
      userId: 'student-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() + 1000 * 60 * 60),
    });
    prisma.user.findUnique.mockResolvedValue({ id: 'student-1', accountType: 'student', suspendedAt: new Date() });

    await expect(service.refresh('still-valid-shape')).rejects.toThrow(UnauthorizedException);
    // Never even attempts to rotate a token for a suspended user.
    expect(prisma.refreshToken.updateMany).not.toHaveBeenCalled();
  });

  it('rejects when the conditional revoke-on-use race is lost (concurrent refresh of the same token)', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue({
      id: 'rt1',
      userId: 'student-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() + 1000 * 60 * 60),
    });
    prisma.user.findUnique.mockResolvedValue({ id: 'student-1', accountType: 'student', suspendedAt: null });
    // Another concurrent call already revoked it between the findUnique
    // read above and this conditional update — count 0 means this caller
    // lost the race, same shape OrderEscrowService.claim uses.
    prisma.refreshToken.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.refresh('racing-token')).rejects.toThrow(UnauthorizedException);
    expect(prisma.refreshToken.create).not.toHaveBeenCalled();
  });

  it('rotates: revokes the used token, issues a new one, and mints a fresh short-lived access token', async () => {
    const { service, prisma, jwt } = makeService();
    prisma.refreshToken.findUnique.mockResolvedValue({
      id: 'rt1',
      userId: 'student-1',
      revokedAt: null,
      expiresAt: new Date(Date.now() + 1000 * 60 * 60),
    });
    prisma.user.findUnique.mockResolvedValue({
      id: 'student-1',
      email: 'student@runit.dev',
      name: 'Ada',
      accountType: 'student',
      campusId: 'campus-1',
      suspendedAt: null,
    });
    prisma.refreshToken.updateMany.mockResolvedValue({ count: 1 });

    const result = await service.refresh('valid-refresh-token');

    expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
      where: { id: 'rt1', revokedAt: null },
      data: { revokedAt: expect.any(Date) },
    });
    expect(prisma.refreshToken.create).toHaveBeenCalledWith({
      data: { userId: 'student-1', tokenHash: expect.any(String), expiresAt: expect.any(Date) },
    });
    // The new refresh token is a genuinely different value from the one
    // just used — not the same row/value handed back.
    expect(result.refreshToken).not.toBe('valid-refresh-token');
    expect(jwt.sign).toHaveBeenCalledWith(
      { sub: 'student-1', accountType: 'student', role: 'user', campusId: 'campus-1' },
      { expiresIn: '1h' },
    );
    expect(result.accessToken).toBe('signed.jwt.token');
  });
});

describe('AuthService.logout', () => {
  it('revokes the refresh token server-side', async () => {
    const { service, prisma } = makeService();

    await service.logout('some-refresh-token');

    expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
      where: { tokenHash: sha256('some-refresh-token'), revokedAt: null },
      data: { revokedAt: expect.any(Date) },
    });
  });

  it('resolves the same generic way for an unknown/already-revoked token — never an oracle for token validity', async () => {
    const { service, prisma } = makeService();
    prisma.refreshToken.updateMany.mockResolvedValue({ count: 0 });

    await expect(service.logout('bogus-or-already-used')).resolves.toEqual({ message: 'Logged out.' });
  });
});
