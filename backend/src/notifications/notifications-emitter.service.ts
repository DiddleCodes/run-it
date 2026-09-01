import { Injectable } from '@nestjs/common';
import { EventEmitter2 } from '@nestjs/event-emitter';
import { NOTIFICATION_EVENT, NotificationEvent } from './notification-event';

// Thin typed wrapper around EventEmitter2 so trigger-point services (order
// escrow, vendors, orders, admin users) depend on one small interface
// instead of importing EventEmitter2 directly and hand-rolling the event
// name/payload shape at every call site. Emission is synchronous-fired but
// NotificationsService's own listener does the actual work (persist,
// push, live channel) — a slow/failing notification path can never block
// or fail the caller's own request, same reasoning as AlertsService.
@Injectable()
export class NotificationsEmitterService {
  constructor(private readonly events: EventEmitter2) {}

  emit(event: NotificationEvent): void {
    this.events.emit(NOTIFICATION_EVENT, event);
  }
}
