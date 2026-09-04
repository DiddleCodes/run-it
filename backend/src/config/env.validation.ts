import * as Joi from 'joi';

export const envValidationSchema = Joi.object({
  NODE_ENV: Joi.string()
    .valid('development', 'test', 'production')
    .default('development'),
  PORT: Joi.number().default(3000),
  DASHBOARD_ORIGIN: Joi.string().optional(),

  DATABASE_URL: Joi.string().uri().required(),
  REDIS_URL: Joi.string().uri().required(),

  PAYSTACK_SECRET_KEY: Joi.string().required(),
  PAYSTACK_PUBLIC_KEY: Joi.string().required(),
  PAYSTACK_BASE_URL: Joi.string().uri().default('https://api.paystack.co'),

  JWT_SECRET: Joi.string().min(16).required(),
  JWT_EXPIRES_IN: Joi.string().default('1d'),

  RESTAURANT_COMMISSION_RATE: Joi.number().min(0).max(1).default(0.15),
  RUNNER_DELIVERY_FEE_SHARE: Joi.number().min(0).max(1).default(0.85),
  DEFAULT_DELIVERY_FEE: Joi.number().integer().min(0).default(35000),

  INTERNAL_SERVICE_API_KEY: Joi.string().min(8).required(),

  AWS_REGION: Joi.string().default('us-east-1'),
  S3_UPLOADS_BUCKET: Joi.string().required(),
  AWS_ACCESS_KEY_ID: Joi.string().required(),
  AWS_SECRET_ACCESS_KEY: Joi.string().required(),
  S3_PUBLIC_BASE_URL: Joi.string().uri().optional(),

  PAYSTACK_WEBHOOK_IP_ALLOWLIST: Joi.string().optional(),
  RECONCILE_INTERVAL_MINUTES: Joi.number().min(1).default(5),
  RECONCILE_STALE_THRESHOLD_MINUTES: Joi.number().min(1).default(10),
  SLACK_ALERT_WEBHOOK_URL: Joi.string().uri().optional(),

  // Optional: Sentry (backend crash/error reporting). Degrades to a logged
  // warning when unset — see instrument.ts. Read directly from
  // process.env there (Sentry.init must run before Nest/ConfigService even
  // exist), but validated here too so a malformed value fails fast at
  // startup like every other env var, instead of silently no-op-ing.
  SENTRY_DSN: Joi.string().uri().optional(),

  // Optional: FcmService degrades to a logged warning (never throws) when
  // unset, so notification infra can ship and be tested before a real
  // Firebase project exists for this app — see FcmService's doc comment.
  FIREBASE_PROJECT_ID: Joi.string().optional(),
  FIREBASE_CLIENT_EMAIL: Joi.string().optional(),
  FIREBASE_PRIVATE_KEY: Joi.string().optional(),

  // Optional: EmailService (Brevo) degrades to a logged warning when unset
  // — see EmailService's doc comment. AuthService's student/email OTP path
  // additionally falls back to a dev-only log when this is unset outside
  // production; that fallback is never reachable in production.
  BREVO_API_KEY: Joi.string().optional(),
  BREVO_SENDER_EMAIL: Joi.string().email().optional(),
  BREVO_SENDER_NAME: Joi.string().optional(),

  // Task 21a: how long an unclaimed order waits before MatchingService
  // re-broadcasts to the same runner pool, and how long before it escalates
  // to a Dispute for admin/restaurant attention. See MatchingService.
  MATCHING_REBROADCAST_SECONDS: Joi.number().min(1).default(20),
  MATCHING_ESCALATE_SECONDS: Joi.number().min(1).default(120),
});
