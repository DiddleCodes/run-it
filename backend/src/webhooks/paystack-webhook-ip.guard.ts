import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import ipRangeCheck from 'ip-range-check';

/**
 * Second factor alongside HMAC signature verification: rejects requests
 * that didn't originate from one of Paystack's published webhook IPs
 * (`paystack.webhookIpAllowlist`).
 *
 * Enforced only in production. Local/staging testing (this collection's own
 * "Simulate Webhook" requests, ngrok tunnels, CI) legitimately calls this
 * endpoint from arbitrary IPs that aren't Paystack's — signature
 * verification alone is what those environments rely on, same as the
 * dev-token endpoint's inverse convention (disabled *in* production instead
 * of enabled only *in* production).
 *
 * Correctness depends on `request.ip` actually reflecting the real client
 * IP. Behind a reverse proxy/load balancer in production, that requires
 * Express's `trust proxy` setting to be configured for that infrastructure
 * (see main.ts) — otherwise every request appears to come from the proxy
 * and this guard will reject genuine Paystack deliveries. See RUNBOOK.md.
 */
@Injectable()
export class PaystackWebhookIpGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    if (this.config.get<string>('nodeEnv') !== 'production') return true;

    const request = context.switchToHttp().getRequest();
    const allowlist = this.config.get<string[]>('paystack.webhookIpAllowlist') ?? [];
    if (allowlist.length === 0) return true;

    const clientIp: string = request.ip;
    if (!ipRangeCheck(clientIp, allowlist)) {
      throw new ForbiddenException('Request did not originate from a recognized Paystack IP');
    }
    return true;
  }
}
