import * as Sentry from '@sentry/nextjs';

// Task 36: Next.js 16's client instrumentation convention (replaces the
// old sentry.client.config.ts pattern). Same minimal, errors-only shape as
// the server/edge configs — deliberately no replayIntegration/
// feedbackIntegration, since those capture DOM/screenshots and this portal
// renders bank details and KYC photo URLs.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0,
    sendDefaultPii: false,
  });
}

// Wires App Router navigations into Sentry's own navigation instrumentation.
export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
