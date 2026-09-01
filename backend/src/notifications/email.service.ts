import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

export interface EmailPayload {
  to: string;
  subject: string;
  html: string;
  text: string;
}

/**
 * Task 20: Brevo's transactional email API, called directly via axios (a
 * single POST) — same convention as AlertsService's Slack webhook, rather
 * than pulling in Brevo's SDK for this. Never throws: a broken/unconfigured
 * BREVO_API_KEY degrades to a logged warning, the same "degrade, don't
 * crash the caller" shape as FcmService/AlertsService. Unlike those two
 * (best-effort side channels where degrading silently is fine), a failed
 * send here blocks the user's actual OTP delivery — so this returns a
 * boolean rather than swallowing the outcome, and it's the caller
 * (AuthService) that decides what, if anything, happens when delivery
 * didn't go out.
 */
@Injectable()
export class EmailService {
  private readonly logger = new Logger(EmailService.name);
  private static readonly BREVO_SEND_URL = 'https://api.brevo.com/v3/smtp/email';

  constructor(private readonly config: ConfigService) {}

  get isConfigured(): boolean {
    return Boolean(this.config.get<string>('brevo.apiKey') && this.config.get<string>('brevo.senderEmail'));
  }

  /** Returns whether the email actually reached Brevo's API. */
  async send(payload: EmailPayload): Promise<boolean> {
    const apiKey = this.config.get<string>('brevo.apiKey');
    const senderEmail = this.config.get<string>('brevo.senderEmail');
    const senderName = this.config.get<string>('brevo.senderName');

    if (!apiKey || !senderEmail) {
      this.logger.warn(`BREVO_API_KEY/BREVO_SENDER_EMAIL not configured — email to ${payload.to} was not sent.`);
      return false;
    }

    try {
      await axios.post(
        EmailService.BREVO_SEND_URL,
        {
          sender: { name: senderName, email: senderEmail },
          to: [{ email: payload.to }],
          subject: payload.subject,
          htmlContent: payload.html,
          textContent: payload.text,
        },
        { headers: { 'api-key': apiKey, 'Content-Type': 'application/json' }, timeout: 5_000 },
      );
      return true;
    } catch (err) {
      this.logger.error(`Failed to send email to ${payload.to} via Brevo: ${(err as Error).message}`);
      return false;
    }
  }
}
