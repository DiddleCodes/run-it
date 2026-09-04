import * as Sentry from '@sentry/nextjs';

// Task 36: covers the edge runtime (proxy.ts's role guard runs here) —
// same minimal, errors-only shape as sentry.server.config.ts.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
}
