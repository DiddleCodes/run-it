import * as Sentry from '@sentry/nextjs';

// Task 36: mirrors backend/src/instrument.ts's own shape exactly — errors
// only (tracesSampleRate: 0, no perf/replay/feedback integrations),
// sendDefaultPii: false. This portal shows bank details and KYC photo
// URLs, so the deliberate choice here is a minimal capture surface rather
// than a wider one with scrubbing bolted on.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
} else {
  console.warn('NEXT_PUBLIC_SENTRY_DSN not configured — server-side crash/error reporting will be logged only, not sent to Sentry.');
}
