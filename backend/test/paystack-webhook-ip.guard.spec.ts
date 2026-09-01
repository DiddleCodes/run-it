import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { PaystackWebhookIpGuard } from '../src/webhooks/paystack-webhook-ip.guard';
import { createConfigMock } from './support/mocks';

function makeContext(ip: string): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => ({ ip }) }),
  } as unknown as ExecutionContext;
}

describe('PaystackWebhookIpGuard', () => {
  it('allows any IP outside production — local/staging testing relies on signature verification alone', () => {
    const guard = new PaystackWebhookIpGuard(
      createConfigMock({ nodeEnv: 'development', 'paystack.webhookIpAllowlist': ['52.31.139.75'] }) as any,
    );

    expect(guard.canActivate(makeContext('127.0.0.1'))).toBe(true);
  });

  it('in production, allows a request from a listed Paystack IP', () => {
    const guard = new PaystackWebhookIpGuard(
      createConfigMock({ nodeEnv: 'production', 'paystack.webhookIpAllowlist': ['52.31.139.75', '52.49.173.169'] }) as any,
    );

    expect(guard.canActivate(makeContext('52.31.139.75'))).toBe(true);
  });

  it('in production, rejects a request from an IP not on the allowlist', () => {
    const guard = new PaystackWebhookIpGuard(
      createConfigMock({ nodeEnv: 'production', 'paystack.webhookIpAllowlist': ['52.31.139.75'] }) as any,
    );

    expect(() => guard.canActivate(makeContext('1.2.3.4'))).toThrow(ForbiddenException);
  });

  it('in production, an explicitly empty allowlist disables the check (escape hatch)', () => {
    const guard = new PaystackWebhookIpGuard(
      createConfigMock({ nodeEnv: 'production', 'paystack.webhookIpAllowlist': [] }) as any,
    );

    expect(guard.canActivate(makeContext('1.2.3.4'))).toBe(true);
  });
});
