import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  // rawBody:true preserves the exact request bytes on req.rawBody alongside
  // the normal parsed req.body, which the Paystack webhook signature check
  // needs (HMAC must be computed over the untouched payload).
  const app = await NestFactory.create(AppModule, { rawBody: true });

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
