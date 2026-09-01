import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { JwtPayload } from '../../auth/jwt-payload.interface';

/**
 * Requires JwtAuthGuard to have already run on the same route. Allows the
 * request through only if the caller is the user_id in the route, or an
 * admin — i.e. "wallet/escrow endpoints require proof of identity for the
 * relevant user_id".
 */
@Injectable()
export class SelfOrAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const user = request.user as JwtPayload;
    const targetUserId = request.params.userId ?? request.body?.userId ?? request.body?.studentUserId;

    if (!user) throw new ForbiddenException('Authentication required');
    if (user.role === 'admin') return true;
    if (user.sub === targetUserId) return true;

    throw new ForbiddenException('You may only act on your own account');
  }
}
