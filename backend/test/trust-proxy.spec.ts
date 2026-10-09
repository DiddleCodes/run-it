import { Controller, Get, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import type { Request } from 'express';
import request from 'supertest';
import { trustProxyHops } from '../src/config/environment';
import { applyTrustProxy } from '../src/http-setup';
import { PaystackWebhookIpGuard } from '../src/webhooks/paystack-webhook-ip.guard';
import { createConfigMock } from './support/mocks';

const PAYSTACK_IP = '52.31.139.75';

@Controller()
class ProbeController {
  @Get('ip')
  ip(@Req() req: Request) {
    return { ip: req.ip };
  }

  @Post('webhook')
  @HttpCode(200)
  @UseGuards(PaystackWebhookIpGuard)
  webhook() {
    return { ok: true };
  }
}

/** A real Express app — exactly what main.ts configures — with trust proxy applied for `env`. */
async function appFor(env: NodeJS.ProcessEnv): Promise<NestExpressApplication> {
  const moduleRef = await Test.createTestingModule({
    controllers: [ProbeController],
    providers: [
      PaystackWebhookIpGuard,
      {
        provide: ConfigService,
        useValue: createConfigMock({ nodeEnv: 'production', 'paystack.webhookIpAllowlist': [PAYSTACK_IP] }),
      },
    ],
  }).compile();
  const app = moduleRef.createNestApplication<NestExpressApplication>({ logger: false });
  applyTrustProxy(app, env);
  await app.init();
  return app;
}

describe('trust proxy — req.ip behind Railway', () => {
  let app: NestExpressApplication;
  afterEach(() => app?.close());

  const ipFor = async (env: NodeJS.ProcessEnv, forwardedFor?: string) => {
    app = await appFor(env);
    const req = request(app.getHttpServer()).get('/ip');
    if (forwardedFor) req.set('X-Forwarded-For', forwardedFor);
    return (await req.expect(200)).body.ip as string;
  };

  it('in production, req.ip is the client the proxy saw, not the proxy', async () => {
    expect(await ipFor({ NODE_ENV: 'production' }, '203.0.113.7')).toBe('203.0.113.7');
  });

  it('with NODE_ENV unset, behaves as production', async () => {
    expect(await ipFor({}, '203.0.113.7')).toBe('203.0.113.7');
  });

  it("ignores an X-Forwarded-For the client forged itself — only the proxy's own entry counts", async () => {
    // The client sent "6.6.6.6"; Railway appended the real address.
    expect(await ipFor({ NODE_ENV: 'production' }, '6.6.6.6, 203.0.113.7')).toBe('203.0.113.7');
  });

  it('locally (development) the header is not trusted at all', async () => {
    expect(await ipFor({ NODE_ENV: 'development' }, '203.0.113.7')).toMatch(/127\.0\.0\.1|::1/);
  });

  it('TRUST_PROXY_HOPS overrides the default — two proxies in front', async () => {
    expect(await ipFor({ NODE_ENV: 'production', TRUST_PROXY_HOPS: '2' }, '198.51.100.4, 10.0.0.2')).toBe(
      '198.51.100.4',
    );
  });

  it('TRUST_PROXY_HOPS=0 turns it off, even in production', async () => {
    expect(await ipFor({ NODE_ENV: 'production', TRUST_PROXY_HOPS: '0' }, '203.0.113.7')).toMatch(
      /127\.0\.0\.1|::1/,
    );
  });

  it('the Paystack webhook allowlist accepts Paystack behind the proxy, and rejects everyone else', async () => {
    app = await appFor({ NODE_ENV: 'production' });
    await request(app.getHttpServer()).post('/webhook').set('X-Forwarded-For', PAYSTACK_IP).expect(200);
    await request(app.getHttpServer()).post('/webhook').set('X-Forwarded-For', '203.0.113.7').expect(403);
    // A forged Paystack IP in front of the real one doesn't get through.
    await request(app.getHttpServer())
      .post('/webhook')
      .set('X-Forwarded-For', `${PAYSTACK_IP}, 203.0.113.7`)
      .expect(403);
  });

  it('without trust proxy, the same real Paystack delivery would be rejected — the bug this fixes', async () => {
    app = await appFor({ NODE_ENV: 'production', TRUST_PROXY_HOPS: '0' });
    await request(app.getHttpServer()).post('/webhook').set('X-Forwarded-For', PAYSTACK_IP).expect(403);
  });
});

describe('trustProxyHops', () => {
  it('defaults to 1 hop outside development/test, 0 inside', () => {
    expect(trustProxyHops({ NODE_ENV: 'production' })).toBe(1);
    expect(trustProxyHops({})).toBe(1);
    expect(trustProxyHops({ NODE_ENV: 'staging' })).toBe(1);
    expect(trustProxyHops({ NODE_ENV: 'development' })).toBe(0);
    expect(trustProxyHops({ NODE_ENV: 'test' })).toBe(0);
  });

  it('rejects a value that is not a whole number', () => {
    expect(() => trustProxyHops({ TRUST_PROXY_HOPS: 'yes' })).toThrow(/TRUST_PROXY_HOPS/);
    expect(() => trustProxyHops({ TRUST_PROXY_HOPS: '-1' })).toThrow(/TRUST_PROXY_HOPS/);
    expect(() => trustProxyHops({ TRUST_PROXY_HOPS: '1.5' })).toThrow(/TRUST_PROXY_HOPS/);
  });
});
