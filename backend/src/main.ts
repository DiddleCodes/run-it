// Task 31: must be the very first import in the entire process — Sentry's
// NestJS instrumentation patches Node's module loader, so anything
// imported above this line would be invisible to it. See instrument.ts.
import './instrument';

import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';
import { applyTrustProxy } from './http-setup';

async function bootstrap() {
  // rawBody:true preserves the exact request bytes on req.rawBody alongside
  // the normal parsed req.body, which the Paystack webhook signature check
  // needs (HMAC must be computed over the untouched payload).
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { rawBody: true });

  // Real client IPs behind Railway's proxy (webhook IP allowlist, rate
  // limits) — RUNBOOK.md → "Checking the resolved client IP".
  const hops = applyTrustProxy(app);
  Logger.log(`trust proxy: ${hops === 0 ? 'off' : `${hops} hop(s)`}`, 'Bootstrap');

  // The web dashboard's Next.js server proxies auth/data calls through its
  // own Route Handlers rather than calling this API from the browser, so
  // this isn't standing in for a same-origin policy — it's a narrow
  // allowlist for the dashboard's own server origin in local dev.
  app.enableCors({
    origin: (process.env.DASHBOARD_ORIGIN ?? 'http://localhost:3001').split(','),
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
}

bootstrap();
