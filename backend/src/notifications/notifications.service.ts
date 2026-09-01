import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { OnEvent } from '@nestjs/event-emitter';
import { Queue } from 'bullmq';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { NOTIFICATION_EVENT, NotificationEvent } from './notification-event';
import { FCM_PUSH_QUEUE } from './notifications.constants';
import { FcmPushJob } from './fcm.processor';
import { NotificationsGateway } from './notifications.gateway';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { DEFAULT_PAGE_SIZE, ListNotificationsQueryDto, MAX_PAGE_SIZE } from './dto/list-notifications-query.dto';

/**
 * Task 19a: the single fan-out point every emitted NotificationEvent goes
 * through — persist first (so a push failure can never lose the event,
 * per the brief's own reasoning), then push + live-channel as best-effort
 * side effects. Trigger points (order escrow, vendors, orders, admin users)
 * never touch Prisma/FCM/the gateway directly; they only construct an event
 * and hand it to NotificationsEmitterService. A future event type (e.g.
 * runner-dispatch) needs no change here — it becomes eligible for this same
 * pipeline the moment a trigger point starts emitting it.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @InjectQueue(FCM_PUSH_QUEUE) private readonly fcmQueue: Queue<FcmPushJob>,
    private readonly gateway: NotificationsGateway,
  ) {}

  // Fire-and-forget from the emitting side (NotificationsEmitterService.emit
  // is synchronous) — this handler runs on its own microtask, so it must
  // never let an error escape as an unhandled rejection. Same "never throw
  // into the caller's request" reasoning as AlertsService: a broken queue
  // connection or DB hiccup here must not turn an otherwise-successful
  // order/account action into a 500.
  @OnEvent(NOTIFICATION_EVENT, { async: true })
  async handle(event: NotificationEvent): Promise<void> {
    try {
      await this.prisma.notification.create({
        data: {
          userId: event.recipientUserId,
          type: event.type,
          title: event.title,
          body: event.body,
          data: (event.data ?? undefined) as Prisma.InputJsonValue | undefined,
        },
      });

      // Every event type this task emits is mobile-relevant (order
      // lifecycle, suspend/reinstate) — see the brief. Queued rather than
      // sent inline so a slow/unreachable FCM never adds latency here,
      // same reasoning as the Paystack webhook queue.
      await this.fcmQueue.add(
        'push',
        { userId: event.recipientUserId, payload: { title: event.title, body: event.body, data: event.data } },
        { attempts: 3, backoff: { type: 'exponential', delay: 3_000 }, removeOnComplete: { count: 1000 }, removeOnFail: { count: 5000 } },
      );

      if (event.type === 'order_placed' && event.data?.vendorId) {
        this.gateway.notifyNewOrder(event.data.vendorId, {
          orderId: event.data.orderId ?? '',
          title: event.title,
          body: event.body,
          data: event.data,
        });
      } else if (event.type === 'order_placed') {
        this.logger.warn(`order_placed event for ${event.recipientUserId} is missing data.vendorId — live channel not notified`);
      }
    } catch (err) {
      this.logger.error(`Failed to process notification event ${event.type} for ${event.recipientUserId}: ${(err as Error).message}`);
    }
  }

  // Upsert-by-token, not by (userId, platform): a token is only ever valid
  // for the app instance that generated it, so re-registering the same
  // token always means "this token belongs here now" — including the case
  // where it previously belonged to a different user on a shared device.
  async registerDeviceToken(userId: string, dto: RegisterDeviceTokenDto) {
    return this.prisma.deviceToken.upsert({
      where: { token: dto.token },
      create: { userId, token: dto.token, platform: dto.platform },
      update: { userId, platform: dto.platform, lastSeenAt: new Date() },
    });
  }

  async removeDeviceToken(userId: string, token: string): Promise<void> {
    await this.prisma.deviceToken.deleteMany({ where: { token, userId } });
  }

  async list(userId: string, query: ListNotificationsQueryDto) {
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);

    const [items, total] = await Promise.all([
      this.prisma.notification.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.notification.count({ where: { userId } }),
    ]);

    return { items, total, page, limit };
  }

  async markRead(userId: string, id: string) {
    const notification = await this.prisma.notification.findUnique({ where: { id } });
    if (!notification || notification.userId !== userId) throw new NotFoundException('Notification not found');
    if (notification.readAt) return notification;

    return this.prisma.notification.update({ where: { id }, data: { readAt: new Date() } });
  }
}
