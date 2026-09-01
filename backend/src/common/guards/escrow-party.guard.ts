import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { PrismaService } from '../../prisma/prisma.service';

export const ESCROW_PARTY_KEY = 'escrowParty';

/** Marks which side of an order's escrow a route is scoped to, for [EscrowPartyGuard]. */
export const EscrowParty = (party: 'runner' | 'student') => SetMetadata(ESCROW_PARTY_KEY, party);

/**
 * Guards escrow release/refund. Accepts the same internal-service-key or
 * admin/internal_service JWT paths as the old InternalOrAdminGuard, PLUS —
 * new — a normal user JWT belonging to the specific party the route is
 * scoped to for that exact order: the assigned runner for /release (they
 * trigger it by scanning the delivery-confirmation code), the ordering
 * student for /refund (they trigger it by cancelling their own order).
 *
 * Neither a runner nor a student should ever hold a blanket internal/admin
 * credential — shipping the internal API key inside the client app would be
 * a real secret-exfiltration vulnerability — so this checks identity against
 * the specific escrow row instead of trusting a broad role claim.
 *
 * TODO(production-hardening): tracked follow-up alongside the dev-token and
 * demo-seeded-user shims — revisit whether self-triggered release/refund
 * should instead go through a server-side delivery-confirmation/cancellation
 * event (with its own audit trail) rather than a direct client call, before
 * this ships to production.
 */
@Injectable()
export class EscrowPartyGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
    private readonly reflector: Reflector,
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
      throw new UnauthorizedException('Internal service key or token required');
    }

    let payload: JwtPayload;
    try {
      payload = await this.jwt.verifyAsync<JwtPayload>(token, {
        secret: this.config.get<string>('jwt.secret'),
      });
    } catch {
      throw new UnauthorizedException('Invalid token');
    }

    if (payload.role === 'admin' || payload.role === 'internal_service') {
      request.user = payload;
      return true;
    }

    const orderId = request.params.orderId as string;
    const escrow = await this.prisma.orderEscrow.findUnique({ where: { orderId } });
    if (!escrow) throw new UnauthorizedException('No escrow for this order');

    const party = this.reflector.get<'runner' | 'student'>(ESCROW_PARTY_KEY, context.getHandler());
    const authorizedUserId =
      party === 'runner'
        ? escrow.runnerUserId
        : await this.prisma.walletTransaction
            .findUniqueOrThrow({ where: { id: escrow.studentWalletTransactionId } })
            .then((txn) => this.prisma.wallet.findUniqueOrThrow({ where: { id: txn.walletId } }))
            .then((wallet) => wallet.userId);

    if (payload.sub !== authorizedUserId) {
      // 403, not 401: this is a valid, authenticated token that just isn't
      // permitted for THIS order — the same distinction SelfOrAdminGuard
      // already draws. Task 17's global "session is no longer valid"
      // handling treats any 401 as "log the user out", so a per-resource
      // authorization failure must never be a 401 or it would wrongly sign
      // out a perfectly legitimate, still-valid session.
      throw new ForbiddenException("You are not a party to this order's escrow");
    }
    request.user = payload;
    return true;
  }
}
