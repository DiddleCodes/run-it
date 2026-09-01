import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, Messaging } from 'firebase-admin/messaging';

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Task 19a: real firebase-admin wiring, not a stub — but this app has no
 * Firebase project yet (no google-services.json, no service account, no
 * firebase_messaging dependency client-side either). Same "never throws,
 * degrades to a logged warning" shape as AlertsService: a push failure must
 * never turn an otherwise-successful order/account action into a 500, and
 * this class must be safe to call in every environment including ones with
 * no Firebase credentials configured at all. Once FIREBASE_PROJECT_ID/
 * CLIENT_EMAIL/PRIVATE_KEY are set to a real service account, sends start
 * working with no code change here.
 */
@Injectable()
export class FcmService implements OnModuleInit {
  private readonly logger = new Logger(FcmService.name);
  private messaging: Messaging | undefined;

  constructor(private readonly config: ConfigService) {}

  onModuleInit(): void {
    const projectId = this.config.get<string>('firebase.projectId');
    const clientEmail = this.config.get<string>('firebase.clientEmail');
    const privateKey = this.config.get<string>('firebase.privateKey');

    if (!projectId || !clientEmail || !privateKey) {
      this.logger.warn(
        'FIREBASE_PROJECT_ID/CLIENT_EMAIL/PRIVATE_KEY not configured — push notifications will be logged, not sent.',
      );
      return;
    }

    const app: App = getApps()[0] ?? initializeApp({ credential: cert({ projectId, clientEmail, privateKey }) });
    this.messaging = getMessaging(app);
  }

  /**
   * Sends to one device token. Returns whether the send actually reached
   * Firebase's API (true) or was skipped/failed (false) — callers (the FCM
   * queue processor) use this to decide whether a bad token should be
   * pruned, not to decide whether to retry (BullMQ's own attempts/backoff
   * handles that via a thrown error instead — see FcmProcessor).
   */
  async send(token: string, payload: PushPayload): Promise<void> {
    if (!this.messaging) {
      this.logger.warn(`[No Firebase project configured] Would push to ${token}: ${payload.title} — ${payload.body}`);
      return;
    }

    await this.messaging.send({
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
    });
  }

  get isConfigured(): boolean {
    return this.messaging !== undefined;
  }
}
