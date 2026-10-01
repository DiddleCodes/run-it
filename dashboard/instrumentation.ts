import * as Sentry from '@sentry/nextjs';

// Task 36: Next.js 16's instrumentation.js convention — register() runs
// once per server instance; onRequestError captures uncaught errors in
// Route Handlers, Server Components, and Server Actions (including
// app/api/proxy/[...path]/route.ts, if fetch()/getSessionToken() ever
// throw there — an ordinary backend error response is forwarded as a
// normal NextResponse, not thrown, so it correctly never reaches this).
export async function register() {
  // A production server without these can't reach the backend or verify a
  // single session — refuse to start rather than fail every request.
  if (process.env.NODE_ENV === 'production') {
    const missing = ['BACKEND_URL', 'JWT_SECRET'].filter((name) => !process.env[name]);
    if (missing.length > 0) {
      throw new Error(`Missing required environment variables: ${missing.join(', ')} (see dashboard/README.md → Production).`);
    }
  }

  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./sentry.server.config');
  }

  if (process.env.NEXT_RUNTIME === 'edge') {
    await import('./sentry.edge.config');
  }
}

export const onRequestError = Sentry.captureRequestError;
