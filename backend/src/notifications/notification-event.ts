import { NotificationType } from '@prisma/client';

// The one event name every emit()/listener pair uses — payload.type is what
// actually distinguishes events, not the EventEmitter2 event name, so a new
// event type (e.g. a future runner-dispatch offer) never needs a new
// @OnEvent() listener wired up anywhere, only a new NotificationType value
// and a new emit() call at its trigger point.
export const NOTIFICATION_EVENT = 'notification' as const;

// Deliberately generic: every emitter resolves its own title/body copy (it
// has the domain context — order id, vendor name, etc. — that
// NotificationsService doesn't) and hands over a fully-formed event.
// NotificationsService's only job is persist + fan out (FCM, live channel),
// never to know what any given event type means.
export interface NotificationEvent {
  type: NotificationType;
  recipientUserId: string;
  title: string;
  body: string;
  // Structured context for the push payload's data field / a dashboard
  // client's own routing (e.g. { orderId, vendorId }). Values must be
  // strings — that's what FCM's data payload requires.
  data?: Record<string, string>;
}
