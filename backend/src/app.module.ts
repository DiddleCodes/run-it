import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { EventEmitterModule } from '@nestjs/event-emitter';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerModule } from '@nestjs/throttler';
import { SentryGlobalFilter, SentryModule } from '@sentry/nestjs/setup';
import Redis from 'ioredis';
import { AdminModule } from './admin/admin.module';
import { AlertsModule } from './alerts/alerts.module';
import { AuthModule } from './auth/auth.module';
import { CampusModule } from './campus/campus.module';
import configuration from './config/configuration';
import { envValidationSchema } from './config/env.validation';
import { NotificationsModule } from './notifications/notifications.module';
import { OrderEscrowModule } from './order-escrow/order-escrow.module';
import { OrdersModule } from './orders/orders.module';
import { PayoutAccountsModule } from './payout-accounts/payout-accounts.module';
import { PrismaModule } from './prisma/prisma.module';
import { RatingsModule } from './ratings/ratings.module';
import { ReconciliationModule } from './reconciliation/reconciliation.module';
import { RedisModule } from './redis/redis.module';
import { RunnerKycModule } from './runner-kyc/runner-kyc.module';
import { UploadsModule } from './uploads/uploads.module';
import { UsersModule } from './users/users.module';
import { VendorsModule } from './vendors/vendors.module';
import { WalletModule } from './wallet/wallet.module';
import { WebhooksModule } from './webhooks/webhooks.module';

@Module({
  imports: [
    // Task 31: must be the first import — @sentry/nestjs's own docs are
    // explicit about this ordering (it needs to wire up before other
    // providers/interceptors are constructed). A no-op when SENTRY_DSN is
    // unset (instrument.ts already skipped Sentry.init in that case).
    SentryModule.forRoot(),
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      validationSchema: envValidationSchema,
      validationOptions: { abortEarly: false },
    }),
    // A dedicated ioredis connection, separate from the app-wide
    // RedisService (webhook dedupe cache) — BullMQ's blocking connection
    // requires `maxRetriesPerRequest: null`, which isn't a setting you'd
    // want on a general-purpose client.
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: new Redis(config.get<string>('redisUrl') as string, { maxRetriesPerRequest: null }),
      }),
    }),
    ScheduleModule.forRoot(),
    // Global: Task 19a's notification pipeline is the first consumer, but
    // any future in-process event (not just notification-shaped ones) can
    // use the same emitter without a new module import anywhere.
    EventEmitterModule.forRoot(),
    // Generous global default — only the webhook endpoint sets a tighter
    // @Throttle() override (see WebhooksController). Nothing else in this
    // API is meaningfully rate-limited by this.
    ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: 1000 }]),
    PrismaModule,
    RedisModule,
    AlertsModule,
    CampusModule,
    AuthModule,
    UsersModule,
    WalletModule,
    PayoutAccountsModule,
    OrderEscrowModule,
    OrdersModule,
    VendorsModule,
    UploadsModule,
    RunnerKycModule,
    RatingsModule,
    WebhooksModule,
    ReconciliationModule,
    AdminModule,
    NotificationsModule,
  ],
  providers: [
    // Task 31: SentryGlobalFilter must be registered before any other
    // APP_FILTER so it sees every exception first — this app has no other
    // exception filters, so this is the only one. It reports 5xx/uncaught
    // errors to Sentry and rethrows to Nest's default handler for the HTTP
    // response either way; it does NOT report expected 4xx HttpExceptions
    // (e.g. a KYC-gate ForbiddenException, a validation 400) — those are
    // correct behavior, not incidents, and reporting every rejected login
    // or unapproved-runner claim attempt would drown out real signal.
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
  ],
})
export class AppModule {}
