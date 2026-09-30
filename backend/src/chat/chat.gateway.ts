import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { PrismaService } from '../prisma/prisma.service';
import { chatRoleFor, findChatOrder } from './chat-access';

export interface ChatMessagePayload {
  id: string;
  orderId: string;
  senderUserId: string;
  body: string;
  createdAt: Date;
  readAt: Date | null;
}

export type JoinOrderAck = { ok: true } | { ok: false; error: string };

/**
 * Task 78: the live half of order chat. Unlike the other two gateways
 * (restaurant-orders, runner-dispatch), which only ever push outward to a
 * room chosen at connect time, clients here ask to join a room per order
 * (`join_order`) — and only the order's student or assigned runner is let
 * in, checked against the same rules as the REST endpoints (chat-access).
 *
 * Messages are sent over REST (POST /orders/:id/messages) so they're
 * persisted before anyone sees them, even if a socket drops mid-send;
 * ChatService then broadcasts them here:
 *   - `message` to the order's room (whoever has that chat open);
 *   - `message_notice` to each participant's own user room (every
 *     connected device of theirs — for the in-app banner and thread list).
 *
 * The app holds this connection only while it's in the foreground, so a
 * user with no connected socket is backgrounded or closed — that's when
 * ChatService pushes via FCM instead ([isUserConnected]).
 *
 * Auth is the REST API's JWT, checked once at handshake, same as the other
 * gateways.
 */
@WebSocketGateway({ namespace: 'order-chat' })
export class ChatGateway implements OnGatewayConnection {
  private readonly logger = new Logger(ChatGateway.name);

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
      client.data.userId = payload.sub;
      await client.join(userRoom(payload.sub));
      client.emit('connected', { userId: payload.sub });
    } catch {
      client.emit('error', { message: 'Invalid or expired token' });
      client.disconnect(true);
    }
  }

  @SubscribeMessage('join_order')
  async joinOrder(@ConnectedSocket() client: Socket, @MessageBody() body: { orderId?: unknown }): Promise<JoinOrderAck> {
    const userId = client.data.userId as string | undefined;
    const orderId = typeof body?.orderId === 'string' ? body.orderId : undefined;
    if (!userId) return { ok: false, error: 'Not authenticated' };
    if (!orderId) return { ok: false, error: 'orderId is required' };

    const order = await findChatOrder(this.prisma, orderId);
    if (!order || !chatRoleFor(order, userId)) {
      this.logger.warn(`User ${userId} was refused the chat room for order ${orderId}`);
      return { ok: false, error: 'You are not part of this order’s chat' };
    }
    await client.join(orderRoom(orderId));
    return { ok: true };
  }

  @SubscribeMessage('leave_order')
  async leaveOrder(@ConnectedSocket() client: Socket, @MessageBody() body: { orderId?: unknown }): Promise<{ ok: true }> {
    if (typeof body?.orderId === 'string') await client.leave(orderRoom(body.orderId));
    return { ok: true };
  }

  broadcastMessage(message: ChatMessagePayload, participantUserIds: string[]): void {
    this.server.to(orderRoom(message.orderId)).emit('message', message);
    for (const userId of participantUserIds) this.server.to(userRoom(userId)).emit('message_notice', message);
  }

  broadcastRead(orderId: string, readerUserId: string, readAt: Date): void {
    this.server.to(orderRoom(orderId)).emit('messages_read', { orderId, readerUserId, readAt });
  }

  /** Whether any of this user's devices has the app open (connected). */
  async isUserConnected(userId: string): Promise<boolean> {
    const sockets = await this.server.in(userRoom(userId)).fetchSockets();
    return sockets.length > 0;
  }
}

export function orderRoom(orderId: string): string {
  return `order:${orderId}`;
}

function userRoom(userId: string): string {
  return `user:${userId}`;
}
