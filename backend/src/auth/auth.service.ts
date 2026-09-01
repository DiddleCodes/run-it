import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { User } from '@prisma/client';
import * as bcrypt from 'bcrypt';
import { createHash, randomBytes } from 'crypto';
import { EmailService } from '../notifications/email.service';
import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from './jwt-payload.interface';

const RESET_TOKEN_TTL_MINUTES = 30;
const BCRYPT_ROUNDS = 12;
const OTP_TTL_MINUTES = 10;
const OTP_LENGTH = 6;

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

    return this.signSession(user);
  }

  // Task 17: replaces the old client-only "any 6-digit code succeeds"
  // stopgap and the dev-token bridge that followed it — this is now the
  // one real, backend-verified way a mobile student/runner account ever
  // gets a session.
  //
  // Task 20: student contacts are always an email (see signup's contact
  // field) and now get the code via a real Brevo delivery, never a log
  // line, in production. Runner contacts are always a phone number — SMS
  // delivery is explicitly out of scope for this task (email-only v1), so
  // there is genuinely no delivery channel for runners yet. Rather than
  // silently breaking runner login, this is a deliberate, known gap: the
  // runner code keeps going out via the server log, in every environment,
  // exactly as it did before this task, until a future SMS task gives it a
  // real channel.
  async requestOtp(contact: string, accountType: OtpAccountType): Promise<{ message: string }> {
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

    if (accountType === 'student') {
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
    } else {
      // Runner (phone) contact — see this method's doc comment above.
      this.logger.log(`OTP requested for ${contact}. Code: ${code} (expires in ${OTP_TTL_MINUTES}m)`);
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
  async verifyOtp(contact: string, code: string, accountType: OtpAccountType, name?: string) {
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

    const isEmail = accountType === 'student';
    let user = await this.prisma.user.findUnique({
      where: isEmail ? { email: contact } : { phone: contact },
    });

    if (!user) {
      user = await this.prisma.user.create({
        data: {
          [isEmail ? 'email' : 'phone']: contact,
          accountType,
          name,
        },
      });
      // Students only, for now — mirrors UsersService.create's own
      // convention (see order_escrows spec).
      if (accountType === 'student') {
        await this.prisma.wallet.create({ data: { userId: user.id, balance: 0 } });
      }
    }

    if (user.suspendedAt) throw invalidCode;

    return this.signSession(user);
  }

  private signSession(user: User) {
    const payload: JwtPayload = {
      sub: user.id,
      accountType: user.accountType as JwtPayload['accountType'],
      role: user.accountType === 'admin' ? 'admin' : 'user',
    };

    return {
      accessToken: this.jwt.sign(payload),
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        accountType: user.accountType,
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

  async me(userId: string) {
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    return {
      id: user.id,
      email: user.email,
      name: user.name,
      accountType: user.accountType,
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

    // TODO: send via a real email provider once one is configured for this
    // backend. Until then, the reset link is logged so the flow is real and
    // testable end to end locally rather than faked on the frontend.
    this.logger.log(
      `Password reset requested for ${email}. Reset link: /reset-password?token=${rawToken} (expires in ${RESET_TOKEN_TTL_MINUTES}m)`,
    );

    return { message };
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
