import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Throttle, ThrottlerGuard } from '@nestjs/throttler';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { DevOnlyGuard } from '../common/guards/dev-only.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { AuthService } from './auth.service';
import { DevTokenDto } from './dev-token.dto';
import { ForgotPasswordDto } from './dto/forgot-password.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { RequestOtpDto } from './dto/request-otp.dto';
import { ResetPasswordDto } from './dto/reset-password.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { JwtPayload } from './jwt-payload.interface';

// Task 18: every route below already carried its own @Throttle() override,
// but none of them took effect — ThrottlerGuard was never bound, the same
// gap webhooks.controller.ts avoided by pairing @Throttle with
// @UseGuards(ThrottlerGuard) on its handler. Binding it here at the
// controller level (rather than repeating it on all five throttled routes)
// makes every existing @Throttle() decorator on this controller live at
// once.
@UseGuards(ThrottlerGuard)
@Controller('auth')
export class AuthController {
  constructor(
    private readonly jwt: JwtService,
    private readonly auth: AuthService,
  ) {}

  /**
   * Dev-only token minting so the wallet/escrow API can be exercised end to
   * end (Postman collection, local testing) without going through the real
   * mobile OTP flow below. Disabled outside non-production by
   * [DevOnlyGuard] — production must issue JWT_SECRET-signed tokens from
   * `/auth/otp/verify` (or `/auth/login` for the dashboard) instead.
   */
  @UseGuards(DevOnlyGuard)
  @Post('dev-token')
  issueDevToken(@Body() dto: DevTokenDto) {
    const payload: JwtPayload = {
      sub: dto.userId,
      accountType: dto.accountType,
      role: dto.role ?? 'user',
    };
    return { accessToken: this.jwt.sign(payload) };
  }

  // Web dashboard auth (restaurant/admin accounts). Mobile student/runner
  // accounts use the OTP flow below — see User.password's doc comment.
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.email, dto.password);
  }

  // Task 17: the mobile student/runner flow's real, backend-verified
  // session issuance — replaces the old dev-token bridge for every real
  // login/signup (fresh OTP entry, and "Forgot passcode?" recovery, which
  // re-uses this same pair against an already-known contact).
  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('otp/request')
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.auth.requestOtp(dto.contact, dto.accountType);
  }

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('otp/verify')
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.contact, dto.code, dto.accountType, dto.name, dto.phone);
  }

  // Task 34: exchanges a still-valid refresh token for a fresh access
  // token (and, via rotation, a fresh refresh token) — what
  // AuthController.handleUnauthorized (Flutter) calls silently before
  // ever forcing a full re-OTP.
  @Throttle({ default: { limit: 20, ttl: 60_000 } })
  @Post('refresh')
  refresh(@Body() dto: RefreshTokenDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  // Task 34: server-side revocation — the refresh token this device was
  // holding can never be replayed again after this, unlike a client-only
  // "forget the token locally" logout.
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('logout')
  logout(@Body() dto: RefreshTokenDto) {
    return this.auth.logout(dto.refreshToken);
  }

  @UseGuards(JwtAuthGuard)
  @Get('me')
  me(@CurrentUser() user: JwtPayload) {
    return this.auth.me(user.sub);
  }

  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('forgot-password')
  forgotPassword(@Body() dto: ForgotPasswordDto) {
    return this.auth.requestPasswordReset(dto.email);
  }

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('reset-password')
  resetPassword(@Body() dto: ResetPasswordDto) {
    return this.auth.resetPassword(dto.token, dto.newPassword);
  }
}
