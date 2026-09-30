import { OrderStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Task 78: who may use an order's chat, in one place — shared by the REST
 * endpoints (ChatService) and the socket room join (ChatGateway) so the two
 * can never disagree.
 *
 * Only two people ever: the order's student and its assigned runner. There
 * is no chat until a runner is assigned (there's nobody to talk to), and
 * sending stops once the order is delivered or cancelled — the history
 * stays readable to both afterwards.
 */
export type ChatRole = 'student' | 'runner';

export interface ChatOrder {
  id: string;
  status: OrderStatus;
  studentUserId: string;
  runnerUserId: string | null;
}

const FINISHED: readonly OrderStatus[] = ['delivered', 'cancelled'];

export function chatRoleFor(order: ChatOrder, userId: string): ChatRole | null {
  if (!order.runnerUserId) return null;
  if (order.studentUserId === userId) return 'student';
  if (order.runnerUserId === userId) return 'runner';
  return null;
}

export function isChatOpen(order: ChatOrder): boolean {
  return order.runnerUserId !== null && !FINISHED.includes(order.status);
}

/** The other participant — the recipient of anything [userId] sends. */
export function otherParticipant(order: ChatOrder, userId: string): string | null {
  const role = chatRoleFor(order, userId);
  if (role === 'student') return order.runnerUserId;
  if (role === 'runner') return order.studentUserId;
  return null;
}

export async function findChatOrder(prisma: PrismaService, orderId: string): Promise<ChatOrder | null> {
  return prisma.order.findUnique({
    where: { id: orderId },
    select: { id: true, status: true, studentUserId: true, runnerUserId: true },
  });
}
