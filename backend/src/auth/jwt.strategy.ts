import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../prisma/prisma.service';
import { JwtPayload } from './jwt-payload.interface';
import { assertUserNotSuspended } from './session-validity.util';

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('jwt.secret') as string,
    });
  }

  // Task 17: every JwtAuthGuard-protected route funnels through here, so
  // this is the one place that can make an already-issued token stop
  // working the instant its account is suspended — not just block the
  // next login. One extra indexed lookup per authenticated request.
  async validate(payload: JwtPayload): Promise<JwtPayload> {
    await assertUserNotSuspended(this.prisma, payload.sub);
    return payload;
  }
}
