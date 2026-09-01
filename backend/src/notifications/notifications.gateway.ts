import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { OnGatewayConnection, OnGatewayDisconnect, WebSocketGateway, WebSocketServer } from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { PrismaService } from '../prisma/prisma.service';

export interface NewOrderPush {
  orderId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Task 19a: the live channel a restaurant dashboard client (follow-up task)
 * will connect to for new-order events — no WebSocket/SSE/polling infra
 * existed anywhere in this backend before this, so this is new, not reused.
 * Its own namespace (rather than the default `/`) keeps room for other live
 * channels later (e.g. a runner-dispatch feed) without this one's
 * connection/auth logic getting entangled with theirs.
 *
 * Auth happens once, at handshake — same JWT the REST API already issues,
 * passed as `auth: { token }` (socket.io v4's standard shape) or a `token`
 * query param for simple non-browser test clients. A connection is only
 * ever joined to its own vendor's room: there is no cross-restaurant
 * broadcast, and an unauthenticated or non-restaurant connection is
 * rejected outright.
 */
@WebSocketGateway({
  namespace: 'restaurant-orders',
  cors: { origin: (process.env.DASHBOARD_ORIGIN ?? 'http://localhost:3001').split(',') },
})
export class NotificationsGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(NotificationsGateway.name);

  @WebSocketServer()
  private server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async handleConnection(client: Socket): Promise<void> {
    const token = (client.handshake.auth?.token as string | undefined) ?? (client.handshake.query?.token as string | undefined);

    if (!token) {
      client.emit('error', { message: 'Authentication required' });
      client.disconnect(true);
      return;
    }

    try {
      const payload = await this.jwt.verifyAsync<JwtPayload>(token, { secret: this.config.get<string>('jwt.secret') });
      const vendor = await this.prisma.vendor.findUnique({ where: { userId: payload.sub } });

      if (!vendor) {
        client.emit('error', { message: 'This channel is for restaurant accounts only' });
        client.disconnect(true);
        return;
      }

      await client.join(vendorRoom(vendor.id));
      client.emit('connected', { vendorId: vendor.id });
      this.logger.log(`Restaurant dashboard connected for vendor ${vendor.id} (socket ${client.id})`);
    } catch {
      client.emit('error', { message: 'Invalid or expired token' });
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    this.logger.debug(`Socket ${client.id} disconnected`);
  }

  notifyNewOrder(vendorId: string, push: NewOrderPush): void {
    this.server.to(vendorRoom(vendorId)).emit('new_order', push);
  }
}

function vendorRoom(vendorId: string): string {
  return `vendor:${vendorId}`;
}
