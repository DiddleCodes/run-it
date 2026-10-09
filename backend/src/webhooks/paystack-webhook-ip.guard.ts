import { CanActivate, ExecutionContext, ForbiddenException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import ipRangeCheck from 'ip-range-check';
import { isDevEnvironment } from '../config/environment';

/**
 * Second factor alongside HMAC signature verification: rejects requests
 * that didn't originate from one of Paystack's published webhook IPs
 * (`paystack.webhookIpAllowlist`).
 *
 * Enforced everywhere except an explicit NODE_ENV of development or test
 * (unset counts as production — isDevEnvironment). Local testing (this
 * collection's own "Simulate Webhook" requests, ngrok tunnels, CI)
 * legitimately calls this endpoint from arbitrary IPs that aren't
 * Paystack's — signature verification alone is what those environments
 * rely on.
 *
 * Correctness depends on `request.ip` actually reflecting the real client
 * IP. Behind a reverse proxy/load balancer in production, that requires
 * Express's `trust proxy` setting to be configured for that infrastructure
 * (TRUST_PROXY_HOPS, applied in main.ts) — otherwise every request appears
 * to come from the proxy and this guard will reject genuine Paystack
 * deliveries. Rejections log the resolved IP and X-Forwarded-For so that
 * case is obvious. See RUNBOOK.md.
 */
@Injectable()
export class PaystackWebhookIpGuard implements CanActivate {
  private readonly logger = new Logger(PaystackWebhookIpGuard.name);

  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    if (isDevEnvironment(this.config.get<string>('nodeEnv'))) return true;

    const request = context.switchToHttp().getRequest();
    const allowlist = this.config.get<string[]>('paystack.webhookIpAllowlist') ?? [];
    if (allowlist.length === 0) return true;

    const clientIp: string = request.ip;
    if (!ipRangeCheck(clientIp, allowlist)) {
      this.logger.warn(
        `Rejected Paystack webhook from ${clientIp} (x-forwarded-for: ${request.headers?.['x-forwarded-for'] ?? 'none'})`,
      );
      throw new ForbiddenException('Request did not originate from a recognized Paystack IP');
    }
    return true;
  }
}
