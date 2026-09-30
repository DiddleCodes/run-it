import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Message } from '@prisma/client';
import { NotificationsEmitterService } from '../notifications/notifications-emitter.service';
import { PrismaService } from '../prisma/prisma.service';
import { ChatOrder, ChatRole, chatRoleFor, findChatOrder, isChatOpen, otherParticipant } from './chat-access';
import { ChatGateway, ChatMessagePayload } from './chat.gateway';

export const MAX_MESSAGE_LENGTH = 1000;
const HISTORY_LIMIT = 500;
const THREADS_LIMIT = 50;
const PUSH_PREVIEW_LENGTH = 140;

/**
 * Task 78: order chat between a student and their assigned runner. Every
 * send is persisted first, then broadcast live (ChatGateway) and — only
 * when the recipient has no connected device, i.e. the app is backgrounded
 * or closed — pushed through the Task 77 FCM pipeline.
 */
@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly gateway: ChatGateway,
    private readonly notifications: NotificationsEmitterService,
  ) {}

  async history(orderId: string, userId: string) {
    const { order, role } = await this.requireParticipant(orderId, userId);
    const [messages, details] = await Promise.all([
      this.prisma.message.findMany({ where: { orderId }, orderBy: { createdAt: 'asc' }, take: HISTORY_LIMIT }),
      this.prisma.order.findUniqueOrThrow({
        where: { id: orderId },
        select: { vendor: { select: { businessName: true } }, studentUser: { select: { name: true } }, runnerUser: { select: { name: true } } },
      }),
    ]);
    return {
      orderId,
      status: order.status,
      canSend: isChatOpen(order),
      myRole: role,
      vendorName: details.vendor.businessName,
      otherPartyName: shortName(role === 'student' ? details.runnerUser?.name : details.studentUser.name, otherRoleLabel(role)),
      messages: messages.map(toPayload),
    };
  }

  async send(orderId: string, userId: string, rawBody: string): Promise<ChatMessagePayload> {
    const body = rawBody.trim();
    if (!body) throw new ConflictException('A message can’t be empty.');
    if (body.length > MAX_MESSAGE_LENGTH) throw new ConflictException(`Keep messages under ${MAX_MESSAGE_LENGTH} characters.`);

    const { order, role } = await this.requireParticipant(orderId, userId);
    if (!isChatOpen(order)) throw new ConflictException('This order is finished, so its chat is closed.');
    const recipientUserId = otherParticipant(order, userId)!;

    const message = toPayload(await this.prisma.message.create({ data: { orderId, senderUserId: userId, body } }));
    this.gateway.broadcastMessage(message, [order.studentUserId, order.runnerUserId!]);

    // Push only when the recipient isn't in the app — if they are, the live
    // `message_notice` above already reached them (and a push would double
    // up with it).
    if (!(await this.gateway.isUserConnected(recipientUserId))) {
      const sender = await this.prisma.user.findUnique({ where: { id: userId }, select: { name: true } });
      this.notifications.emit({
        type: 'chat_message',
        recipientUserId,
        title: role === 'runner' ? `${shortName(sender?.name, 'Your runner')} (your runner)` : shortName(sender?.name, 'Your customer'),
        body: body.length > PUSH_PREVIEW_LENGTH ? `${body.slice(0, PUSH_PREVIEW_LENGTH - 1)}…` : body,
        data: { orderId },
        persist: false,
      });
    }
    return message;
  }

  /** Marks everything the other party sent as read by [userId]. */
  async markRead(orderId: string, userId: string): Promise<{ updated: number }> {
    await this.requireParticipant(orderId, userId);
    const readAt = new Date();
    const { count } = await this.prisma.message.updateMany({
      where: { orderId, senderUserId: { not: userId }, readAt: null },
      data: { readAt },
    });
    if (count > 0) this.gateway.broadcastRead(orderId, userId, readAt);
    return { updated: count };
  }

  /**
   * Every order [userId] has a chat on (a runner was assigned), newest
   * activity first — the runner's Messages tab. Includes finished orders:
   * their history stays readable.
   */
  async threads(userId: string) {
    const orders = await this.prisma.order.findMany({
      where: { runnerUserId: { not: null }, OR: [{ studentUserId: userId }, { runnerUserId: userId }] },
      orderBy: { updatedAt: 'desc' },
      take: THREADS_LIMIT,
      select: {
        id: true,
        status: true,
        studentUserId: true,
        runnerUserId: true,
        updatedAt: true,
        vendor: { select: { businessName: true } },
        studentUser: { select: { name: true } },
        runnerUser: { select: { name: true } },
      },
    });
    if (orders.length === 0) return [];
    const ids = orders.map((o) => o.id);

    const [latest, unread] = await Promise.all([
      this.prisma.message.findMany({ where: { orderId: { in: ids } }, orderBy: { createdAt: 'desc' }, distinct: ['orderId'] }),
      this.prisma.message.groupBy({
        by: ['orderId'],
        where: { orderId: { in: ids }, senderUserId: { not: userId }, readAt: null },
        _count: { _all: true },
      }),
    ]);
    const latestByOrder = new Map(latest.map((m) => [m.orderId, m]));
    const unreadByOrder = new Map(unread.map((u) => [u.orderId, u._count._all]));

    return orders
      .map((order) => {
        const role = chatRoleFor(order, userId) as ChatRole;
        const last = latestByOrder.get(order.id);
        return {
          orderId: order.id,
          status: order.status,
          canSend: isChatOpen(order),
          myRole: role,
          vendorName: order.vendor.businessName,
          otherPartyName: shortName(role === 'student' ? order.runnerUser?.name : order.studentUser.name, otherRoleLabel(role)),
          lastMessage: last ? toPayload(last) : null,
          unreadCount: unreadByOrder.get(order.id) ?? 0,
          lastActivityAt: last?.createdAt ?? order.updatedAt,
        };
      })
      .sort((a, b) => b.lastActivityAt.getTime() - a.lastActivityAt.getTime());
  }

  private async requireParticipant(orderId: string, userId: string): Promise<{ order: ChatOrder; role: ChatRole }> {
    const order = await findChatOrder(this.prisma, orderId);
    if (!order) throw new NotFoundException('Order not found');
    const role = chatRoleFor(order, userId);
    if (!role) {
      throw new ForbiddenException(
        order.runnerUserId ? 'Only this order’s student and runner can use its chat.' : 'Chat opens once a runner is assigned.',
      );
    }
    return { order, role };
  }
}

// "Chidi Okafor" -> "Chidi O." — same privacy-preserving short form Task 73
// uses for runner names, applied to both sides of a chat.
function shortName(name: string | null | undefined, fallback: string): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return fallback;
  if (parts.length === 1) return parts[0];
  return `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.`;
}

function otherRoleLabel(role: ChatRole): string {
  return role === 'student' ? 'Your runner' : 'Your customer';
}

function toPayload(m: Message): ChatMessagePayload {
  return { id: m.id, orderId: m.orderId, senderUserId: m.senderUserId, body: m.body, createdAt: m.createdAt, readAt: m.readAt };
}
