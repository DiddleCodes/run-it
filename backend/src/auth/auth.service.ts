import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { User } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { CampusService } from '../campus/campus.service';
import { EmailService } from '../notifications/email.service';
import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from './jwt-payload.interface';
import { SESSION_INVALID_MESSAGE } from './session-validity.util';

const RESET_TOKEN_TTL_MINUTES = 30;
const BCRYPT_ROUNDS = 12;
const OTP_TTL_MINUTES = 10;
const OTP_LENGTH = 6;

// Task 34: only the mobile OTP flow's access tokens get this short a
// lifetime — the dashboard's login() keeps the module-default JWT_EXPIRES_IN
// (still 1d; unchanged) since a real refresh mechanism for it is
// deliberately out of this task's scope (see login()'s own note). A
// student/runner session can legitimately run for hours (a runner mid
// delivery shift, a student browsing between classes) — too short an
// access token would mean constant re-auth, too long defeats the point of
// having a revocable refresh token at all. 1h keeps the exposure window
// tight while staying well above this app's typical single-screen request
// cadence, and AuthController.handleUnauthorized's silent refresh (Flutter)
// makes the hourly rollover invisible to the user — it's the 30-day
// refresh token, not the access token, that a device actually goes a long
// time without needing to re-mint.
const MOBILE_ACCESS_TOKEN_TTL = '1h';
const REFRESH_TOKEN_TTL_DAYS = 30;

/** Only these account types ever authenticate with a password — the web dashboard. */
const PASSWORD_LOGIN_ACCOUNT_TYPES = ['restaurant', 'admin'] as const;

/** The only two account types the mobile OTP flow ever authenticates. */
type OtpAccountType = 'student' | 'runner';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly email: EmailService,
    private readonly config: ConfigService,
    private readonly campus: CampusService,
  ) {}

  async login(email: string, password: string) {
    // Same generic failure for "no such user", "wrong account type", and
    // "wrong password" — never tell a caller which of these it was.
    const invalidCredentials = new UnauthorizedException('Invalid email or password');

    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !user.password) throw invalidCredentials;
    if (!(PASSWORD_LOGIN_ACCOUNT_TYPES as readonly string[]).includes(user.accountType)) {
      throw invalidCredentials;
    }

    const matches = await bcrypt.compare(password, user.password);
    if (!matches) throw invalidCredentials;

    // Task 13c: admin suspend/reinstate. Same generic message as any other
    // rejection here — a suspended account shouldn't be distinguishable
    // from a wrong password by the error alone. There's no session store
    // to revoke an already-issued JWT, so this blocks only the *next*
    // login, not any currently-active session.
    if (user.suspendedAt) throw invalidCredentials;

    // Task 34: deliberately NOT given a refresh token or a shortened
    // access-token lifetime — that's the mobile OTP flow's own change
    // (verifyOtp below). A real refresh mechanism for the web dashboard
    // (restaurant/admin) is explicitly a separate, later task; this stays
    // on the original module-default JWT_EXPIRES_IN token, unchanged.
    return this.signSession(user);
  }

  // Task 17: replaces the old client-only "any 6-digit code succeeds"
  // stopgap and the dev-token bridge that followed it — this is now the
  // one real, backend-verified way a mobile student/runner account ever
  // gets a session.
  //
  // Task 20 / Task 28: both student and runner contacts are always an
  // email now (see signup's contact field) and always get the code via a
  // real Brevo delivery, never a log line, in production. Runners used to
  // sign up with a phone number and had no real delivery channel (SMS was
  // out of scope), so the code went out via the server log in every
  // environment — Task 28 closes that gap by collecting a real email at
  // runner signup instead, so runners get exactly the same delivery path
  // students already have. Phone is still collected separately at signup
  // (see verifyOtp's `phone` param) — it's used for admin dispute contact,
  // not OTP delivery, so dropping it here would break that.
  async requestOtp(contact: string, accountType: OtpAccountType): Promise<{ message: string }> {
    // Task 26: the real enforcement point — checked before any OTP row is
    // created or any email is sent, so an unrecognized domain never costs
    // a wasted Brevo send and never leaves a live, unusable code lying
    // around. Lets CampusService's UnprocessableEntityException (with its
    // own honest, specific message) propagate as-is rather than being
    // folded into the generic invalid/expired-code response verifyOtp
    // uses — unlike a wrong code or a suspended account, "your school
    // isn't supported yet" is not a case this app has any reason to hide
    // from a genuine prospective user.
    if (accountType === 'student') {
      await this.campus.resolveByEmail(contact);
    }

    const code = this.generateOtpCode();
    const codeHash = this.hashToken(code);

    // At most one live (unconsumed) code per contact — a resend
    // invalidates whatever was sent before it, rather than letting an old
    // code linger as a second valid guess.
    await this.prisma.$transaction([
      this.prisma.otpVerification.deleteMany({ where: { contact, consumedAt: null } }),
      this.prisma.otpVerification.create({
        data: { contact, codeHash, expiresAt: new Date(Date.now() + OTP_TTL_MINUTES * 60_000) },
      }),
    ]);

    // Task 28: student and runner both deliver via the same real Brevo
    // path now — no more accountType branch here, and no more
    // unconditional plaintext log for runners.
    const sent = await this.email.send({
      to: contact,
      subject: 'Your RUN-It verification code',
      html: this.otpEmailHtml(code),
      text: `Your RUN-It verification code is ${code}. It expires in ${OTP_TTL_MINUTES} minutes. If you didn't request this, you can safely ignore this email.`,
    });

    if (!sent && this.config.get<string>('nodeEnv') !== 'production') {
      // DEV ONLY: no Brevo credentials configured locally, or the send
      // failed. Never reachable in production — see EmailService.send's
      // warning log for the production-equivalent signal, which never
      // includes the code itself.
      this.logger.warn(`[DEV ONLY] Brevo not configured/send failed — OTP for ${contact}: ${code}`);
    }

    // Same generic response regardless of whether a User already exists
    // for this contact — mirrors requestPasswordReset's own
    // no-enumeration convention.
    return { message: 'If this contact is valid, a verification code has been sent.' };
  }

  private otpEmailHtml(code: string): string {
    return `
      <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; color: #1a1a1a;">
        <h2 style="margin: 0 0 16px;">RUN-It verification code</h2>
        <p style="margin: 0 0 24px; font-size: 15px; line-height: 1.5;">Enter this code in the app to continue:</p>
        <p style="margin: 0 0 24px; font-size: 32px; font-weight: 700; letter-spacing: 8px; text-align: center;">${code}</p>
        <p style="margin: 0 0 8px; font-size: 14px; color: #555;">This code expires in ${OTP_TTL_MINUTES} minutes.</p>
        <p style="margin: 0; font-size: 13px; color: #888;">If you didn't request this, you can safely ignore this email.</p>
      </div>
    `.trim();
  }

  // Verifies the code, then finds-or-creates the User row (folding what
  // used to be the client-orchestrated POST /users + /auth/dev-token pair
  // into one real, atomic, suspension-checked step) and mints a session
  // the same way login() does.
  // Task 28: `phone` is only ever used on first verify (account creation),
  // exactly like `name` — a returning user's already-stored phone is left
  // untouched. Only meaningful for a runner signup; a student contact has
  // never collected one, and this is `undefined` there.
  async verifyOtp(contact: string, code: string, accountType: OtpAccountType, name?: string, phone?: string) {
    // Same generic rejection for "wrong code", "expired/already-used
    // code", and "suspended account" — see login()'s doc comment for why
    // a suspended account must not be distinguishable from any other
    // verification failure by the response alone.
    const invalidCode = new UnauthorizedException('Invalid or expired code');

    const record = await this.prisma.otpVerification.findFirst({
      where: { contact, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });
    if (!record || record.codeHash !== this.hashToken(code)) throw invalidCode;

    // Consumed immediately so the same code can never be replayed for a
    // second session.
    await this.prisma.otpVerification.update({ where: { id: record.id }, data: { consumedAt: new Date() } });

    // Task 28: both student and runner contacts are an email now — the
    // old isEmail/phone-lookup branch is gone along with the phone-based
    // OTP path itself.
    let user = await this.prisma.user.findUnique({ where: { email: contact } });

    if (!user) {
      // Task 26: re-resolved here (requestOtp already checked this at
      // request time) rather than trusted from that earlier call — the
      // two are seconds-to-minutes apart, and re-checking against
      // whatever the Campus directory says *right now* is what actually
      // makes this the enforcement point, not a redundant formality. A
      // runner never gets a campusId here — that's admin-assigned later
      // (AdminUsersService.assignCampus), never derived from their email
      // contact.
      const campusId = accountType === 'student' ? (await this.campus.resolveByEmail(contact)).id : null;

      user = await this.prisma.user.create({
        data: {
          email: contact,
          phone,
          accountType,
          name,
          campusId,
        },
      });
      // Task 33: runners get a wallet too now — delivery earnings land
      // there instead of a direct Paystack transfer (see
      // OrderEscrowService.release()'s runner leg). Existing runner
      // accounts predating this change are backfilled by migration
      // 20260903223224_backfill_runner_wallets. Restaurants still have no
      // wallet — their payout stays direct-to-bank, unchanged.
      if (accountType === 'student' || accountType === 'runner') {
        await this.prisma.wallet.create({ data: { userId: user.id, balance: 0 } });
      }
    }

    if (user.suspendedAt) throw invalidCode;

    // Task 34: a real, revocable, rotating refresh token issued alongside
    // the (now short-lived) access token — replaces the old "no refresh at
    // all, just a 1-day token and a full re-OTP once it's gone" behavior.
    const refreshToken = await this.issueRefreshToken(user.id);
    return { ...this.signSession(user, { expiresIn: MOBILE_ACCESS_TOKEN_TTL }), refreshToken };
  }

  /**
   * Task 34: exchanges a valid, not-yet-used refresh token for a fresh
   * access token — and, via rotation, a fresh refresh token too. The old
   * refresh token is revoked in the same step it's read, so a second use
   * of it (a legitimate double-tap race, or a replayed leaked token) is
   * rejected the same generic way an unknown one is — there is exactly one
   * valid refresh token per "session lineage" at any moment, never two.
   * Re-checks suspension explicitly rather than trusting the token alone:
   * AdminUsersService.suspend already revokes every stored refresh token
   * the instant it runs, but this closes the narrow race where a refresh
   * lands in the same instant as a suspension that hasn't committed yet.
   */
  async refresh(rawRefreshToken: string) {
    const invalid = new UnauthorizedException(SESSION_INVALID_MESSAGE);
    const tokenHash = this.hashToken(rawRefreshToken);
    const stored = await this.prisma.refreshToken.findUnique({ where: { tokenHash } });
    if (!stored || stored.revokedAt || stored.expiresAt < new Date()) throw invalid;

    const user = await this.prisma.user.findUnique({ where: { id: stored.userId } });
    if (!user || user.suspendedAt) throw invalid;

    // Conditional update, same shape this codebase already uses for every
    // other "only the first caller wins" race (OrderEscrowService.claim,
    // WalletService.initiateWithdrawal's debit): only succeeds if this
    // token is still unrevoked at the moment of the write, so two
    // concurrent uses of the same refresh token can't both mint a session
    // from it.
    const revoked = await this.prisma.refreshToken.updateMany({
      where: { id: stored.id, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (revoked.count === 0) throw invalid;

    const refreshToken = await this.issueRefreshToken(user.id);
    return { ...this.signSession(user, { expiresIn: MOBILE_ACCESS_TOKEN_TTL }), refreshToken };
  }

  /**
   * Task 34: server-side revocation, not just "the client stopped sending
   * it" — a logged-out device's refresh token can never be replayed
   * afterward (by that device, or anyone who'd captured it) to mint a new
   * access token. Always resolves the same generic way regardless of
   * whether the token was real/already-revoked/unknown — logging out is
   * never an oracle for "was this a valid token."
   */
  async logout(rawRefreshToken: string): Promise<{ message: string }> {
    const tokenHash = this.hashToken(rawRefreshToken);
    await this.prisma.refreshToken.updateMany({
      where: { tokenHash, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { message: 'Logged out.' };
  }

  private async issueRefreshToken(userId: string): Promise<string> {
    const rawToken = randomBytes(32).toString('hex');
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: this.hashToken(rawToken),
        expiresAt: new Date(Date.now() + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60_000),
      },
    });
    return rawToken;
  }

  private signSession(user: User, options?: { expiresIn: string }) {
    const payload: JwtPayload = {
      sub: user.id,
      accountType: user.accountType as JwtPayload['accountType'],
      role: user.accountType === 'admin' ? 'admin' : 'user',
      campusId: user.campusId,
    };

    return {
      accessToken: options ? this.jwt.sign(payload, { expiresIn: options.expiresIn }) : this.jwt.sign(payload),
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        accountType: user.accountType,
        campusId: user.campusId,
      },
    };
  }

  private generateOtpCode(): string {
    // Not cryptographically sensitive beyond the same guessing-resistance
    // a real SMS OTP already has (10-minute expiry, single-use, backed by
    // a random draw) — Math.random() is fine here, this isn't a token
    // whose bytes are the credential itself (unlike the reset-token flow's
    // randomBytes(32), which is).
    return Math.floor(Math.random() * 10 ** OTP_LENGTH)
      .toString()
      .padStart(OTP_LENGTH, '0');
  }

  // Task 29: also the real profile-refresh call the Flutter app polls
  // while a runner's KYC is under review (`AuthController.refreshProfile`)
  // — previously unused by the app, now the one place a stale locally
  // cached kycStatus (e.g. resumed via biometric login) gets corrected
  // against whatever the backend actually says right now.
  async me(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { runnerKyc: true },
    });
    return {
      id: user.id,
      email: user.email,
      name: user.name,
      accountType: user.accountType,
      kycStatus: user.runnerKyc?.status ?? null,
      kycRejectionReason: user.runnerKyc?.rejectionReason ?? null,
      runnerType: user.runnerKyc?.runnerType ?? null,
      vehicleType: user.runnerKyc?.vehicleType ?? null,
      vehiclePlate: user.runnerKyc?.vehiclePlate ?? null,
    };
  }

  /**
   * Always resolves with the same generic message regardless of whether the
   * email matches an account — callers must never be able to enumerate
   * registered emails via this endpoint.
   */
  async requestPasswordReset(email: string): Promise<{ message: string }> {
    const message = 'If that email is registered, a password reset link has been sent.';

    const user = await this.prisma.user.findUnique({ where: { email } });
    if (!user || !(PASSWORD_LOGIN_ACCOUNT_TYPES as readonly string[]).includes(user.accountType)) {
      return { message };
    }

    const rawToken = randomBytes(32).toString('hex');
    const tokenHash = this.hashToken(rawToken);

    await this.prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash,
        expiresAt: new Date(Date.now() + RESET_TOKEN_TTL_MINUTES * 60_000),
      },
    });

    // Same real Brevo path as requestOtp() above — see that method's own
    // comment for why there's no accountType branch here either.
    const resetLink = `${this.config.get<string>('dashboardUrl')}/reset-password?token=${rawToken}`;
    const sent = await this.email.send({
      to: email,
      subject: 'Reset your RUN-It password',
      html: this.resetPasswordEmailHtml(resetLink),
      text: `Reset your RUN-It password: ${resetLink} (expires in ${RESET_TOKEN_TTL_MINUTES} minutes). If you didn't request this, you can safely ignore this email.`,
    });

    if (!sent && this.config.get<string>('nodeEnv') !== 'production') {
      // DEV ONLY: no Brevo credentials configured locally, or the send
      // failed. Never reachable in production — see EmailService.send's
      // warning log for the production-equivalent signal, which never
      // includes the link itself.
      this.logger.warn(`[DEV ONLY] Brevo not configured/send failed — reset link for ${email}: ${resetLink}`);
    }

    return { message };
  }

  private resetPasswordEmailHtml(resetLink: string): string {
    return `
      <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 480px; margin: 0 auto; padding: 24px; color: #1a1a1a;">
        <h2 style="margin: 0 0 16px;">Reset your RUN-It password</h2>
        <p style="margin: 0 0 24px; font-size: 15px; line-height: 1.5;">Click the button below to choose a new password:</p>
        <p style="margin: 0 0 24px; text-align: center;">
          <a href="${resetLink}" style="display: inline-block; padding: 12px 28px; background: #7A1636; color: #fff; text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 14px;">Reset password</a>
        </p>
        <p style="margin: 0 0 8px; font-size: 14px; color: #555;">This link expires in ${RESET_TOKEN_TTL_MINUTES} minutes.</p>
        <p style="margin: 0; font-size: 13px; color: #888;">If you didn't request this, you can safely ignore this email.</p>
      </div>
    `.trim();
  }

  async resetPassword(token: string, newPassword: string): Promise<{ message: string }> {
    const tokenHash = this.hashToken(token);
    const resetToken = await this.prisma.passwordResetToken.findUnique({ where: { tokenHash } });

    if (!resetToken || resetToken.usedAt || resetToken.expiresAt < new Date()) {
      throw new UnauthorizedException('This reset link is invalid or has expired');
    }

    const passwordHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);

    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: resetToken.userId },
        data: { password: passwordHash },
      }),
      this.prisma.passwordResetToken.update({
        where: { id: resetToken.id },
        data: { usedAt: new Date() },
      }),
    ]);

    return { message: 'Password updated. You can now sign in.' };
  }

  private hashToken(rawToken: string): string {
    return createHash('sha256').update(rawToken).digest('hex');
  }
}
