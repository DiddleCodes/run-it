import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

/**
 * Best-effort notification for anything that must not fail silently into
 * logs nobody reads: reconciliation failures, transfer failures, an escrow
 * stuck past the reconciliation threshold with no resolution. A Slack
 * incoming webhook is sufficient for now — swap the transport here if that
 * changes, callers don't need to know.
 *
 * Deliberately never throws: alerting is a side-channel, not part of the
 * money-moving code path. A broken SLACK_ALERT_WEBHOOK_URL must never turn
 * an otherwise-successful (or already-logged) operation into a 500.
 */
@Injectable()
export class AlertsService {
  private readonly logger = new Logger(AlertsService.name);

  constructor(private readonly config: ConfigService) {}

  async send(message: string, context?: Record<string, unknown>): Promise<void> {
    const webhookUrl = this.config.get<string>('alerts.slackWebhookUrl');
    const fullMessage = context ? `${message}\n\`\`\`${JSON.stringify(context, null, 2)}\`\`\`` : message;

    if (!webhookUrl) {
      this.logger.warn(`[ALERT, no SLACK_ALERT_WEBHOOK_URL configured] ${fullMessage}`);
      return;
    }

    try {
      await axios.post(webhookUrl, { text: `:rotating_light: RUN-It Payments: ${fullMessage}` }, { timeout: 5_000 });
    } catch (err) {
      this.logger.error(`Failed to deliver Slack alert: ${(err as Error).message}. Original alert: ${fullMessage}`);
    }
  }
}
