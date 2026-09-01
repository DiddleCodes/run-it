import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { assertUserNotSuspended } from '../../auth/session-validity.util';
import { PrismaService } from '../../prisma/prisma.service';

/**
 * Pure admin-only gate — unlike InternalOrAdminGuard, there is no internal
 * service-key bypass here. Every /admin/* route uses this: an internal
 * service has no legitimate reason to call an admin endpoint.
 */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();

    const authHeader: string | undefined = request.headers['authorization'];
    const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : undefined;
    if (!token) {
      throw new UnauthorizedException('Admin token required');
    }

    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(token, {
        secret: this.config.get<string>('jwt.secret'),
      });
      if (payload.role !== 'admin') {
        throw new UnauthorizedException('Admin role required');
      }
    } catch {
      throw new UnauthorizedException('Invalid or insufficient token');
    }

    // Task 17: an admin's own account can be suspended too — this guard
    // doesn't go through JwtStrategy (it verifies the token itself), so it
    // needs the same per-request check applied there.
    await assertUserNotSuspended(this.prisma, payload.sub);
    request.user = payload;
    return true;
  }
}
