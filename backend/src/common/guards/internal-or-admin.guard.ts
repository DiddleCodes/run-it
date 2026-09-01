import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { JwtPayload } from '../../auth/jwt-payload.interface';

/**
 * Escrow release/refund must never be callable by an arbitrary client — only
 * by the delivery-confirmation flow (presenting the internal service shared
 * secret) or an admin (presenting an admin-role JWT). This guard is
 * self-contained rather than composed from JwtAuthGuard so that the internal
 * API key path can short-circuit before any JWT is required at all.
 */
@Injectable()
export class InternalOrAdminGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();

    const internalKey = request.headers['x-internal-api-key'];
    if (internalKey && internalKey === this.config.get<string>('internalServiceApiKey')) {
      request.user = { sub: 'internal-service', role: 'internal_service' } satisfies JwtPayload;
      return true;
    }

    const authHeader: string | undefined = request.headers['authorization'];
    const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : undefined;
    if (!token) {
      throw new UnauthorizedException('Internal service key or admin token required');
    }

    try {
      const payload = await this.jwt.verifyAsync<JwtPayload>(token, {
        secret: this.config.get<string>('jwt.secret'),
      });
      if (payload.role !== 'admin' && payload.role !== 'internal_service') {
        throw new UnauthorizedException('Admin or internal service role required');
      }
      request.user = payload;
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or insufficient token');
    }
  }
}
