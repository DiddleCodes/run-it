import * as Sentry from '@sentry/nestjs';
import { config as loadDotenv } from 'dotenv';

// Load .env directly rather than relying on ConfigModule.forRoot() —
// that only populates process.env once NestFactory.create(AppModule) runs
// deeper in main.ts, which is after this file has already executed. A
// no-op in real deployments (env vars are already set by the platform
// there); .env is a local-dev-only convenience already gitignored, same
// as everywhere else this app reads it.
loadDotenv();

// Task 31: must be imported before any other module — Sentry's NestJS
// instrumentation patches Node's module loader itself, so anything
// imported before this file runs (including Nest, Prisma, axios) would be
// invisible to it. This is why it's a separate file imported as the very
// first line of main.ts, rather than initialized inside AppModule/main()
// like every other integration in this codebase — Sentry's own docs are
// explicit that this is the one integration that can't follow the usual
// ConfigService-driven init order.
//
// Read directly from process.env (ConfigService doesn't exist yet at this
// point in the bootstrap). Same graceful-degradation shape as every other
// optional integration here (AlertsService, FcmService, EmailService): an
// unset SENTRY_DSN logs a warning and continues rather than failing
// startup.
const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    // Errors only for now — no perf/tracing sampling. This app has no
    // latency-monitoring requirement yet, and tracesSampleRate: 0 keeps
    // Sentry's footprint limited to exactly what Task 31 asked for.
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
} else {
  // eslint-disable-next-line no-console -- Nest's Logger isn't available this early in bootstrap.
  console.warn('SENTRY_DSN not configured — crash/error reporting will be logged only, not sent to Sentry.');
}
