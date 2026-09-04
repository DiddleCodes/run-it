export default () => ({
  nodeEnv: process.env.NODE_ENV,
  port: parseInt(process.env.PORT ?? '3000', 10),

  databaseUrl: process.env.DATABASE_URL,
  redisUrl: process.env.REDIS_URL,

  paystack: {
    secretKey: process.env.PAYSTACK_SECRET_KEY,
    publicKey: process.env.PAYSTACK_PUBLIC_KEY,
    baseUrl: process.env.PAYSTACK_BASE_URL ?? 'https://api.paystack.co',
    // Must match the URL the Flutter client passes to flutter_paystack_plus's
    // `callBackUrl` — that package only fires its onSuccess/onClosed
    // callbacks once the in-app webview navigates to this exact URL, so the
    // two sides have to agree on it even though nothing ever actually loads
    // there (the client intercepts the navigation first).
    callbackUrl: process.env.PAYSTACK_CALLBACK_URL ?? 'https://runit.app/payments/callback',
    // Paystack's published webhook source IPs (as of their docs). Checked
    // as a second factor alongside HMAC signature verification — see
    // PaystackWebhookIpGuard. Overridable via env because Paystack can
    // change these, and because a local Postgres/ngrok/staging setup often
    // needs to add its own tunnel IP to test webhooks at all.
    webhookIpAllowlist: (
      process.env.PAYSTACK_WEBHOOK_IP_ALLOWLIST ?? '52.31.139.75,52.49.173.169,52.214.14.220'
    )
      .split(',')
      .map((ip) => ip.trim())
      .filter(Boolean),
  },

  jwt: {
    secret: process.env.JWT_SECRET,
    expiresIn: process.env.JWT_EXPIRES_IN ?? '1d',
  },

  // The web dashboard's own public URL — distinct from DASHBOARD_ORIGIN
  // (that one's CORS-specific, checked against the request's Origin
  // header). Used only to build absolute links in outbound emails (e.g.
  // password reset), which need a real, browsable URL rather than a bare
  // path.
  dashboardUrl: process.env.DASHBOARD_URL ?? 'http://localhost:3001',

  escrow: {
    // 0-1, applied to the food subtotal only — never the delivery fee.
    restaurantCommissionRate: Number(process.env.RESTAURANT_COMMISSION_RATE ?? 0.15),
    // 0-1, the runner's cut of the delivery fee; the platform keeps the
    // remainder of the delivery fee (never the food subtotal).
    runnerDeliveryFeeShare: Number(process.env.RUNNER_DELIVERY_FEE_SHARE ?? 0.85),
    // Kobo. Flat for now — a clear extension point for future distance-based
    // tiering, not built yet.
    defaultDeliveryFeeKobo: Number(process.env.DEFAULT_DELIVERY_FEE ?? 35000),
  },

  internalServiceApiKey: process.env.INTERNAL_SERVICE_API_KEY,

  s3: {
    region: process.env.AWS_REGION ?? 'us-east-1',
    bucket: process.env.S3_UPLOADS_BUCKET,
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    // Falls back to the bucket's default virtual-hosted-style URL when no
    // CDN/custom domain is fronting it.
    publicBaseUrl:
      process.env.S3_PUBLIC_BASE_URL ??
      `https://${process.env.S3_UPLOADS_BUCKET}.s3.${process.env.AWS_REGION ?? 'us-east-1'}.amazonaws.com`,
  },

  reconciliation: {
    // How often the sweep runs.
    intervalMinutes: Number(process.env.RECONCILE_INTERVAL_MINUTES ?? 5),
    // A pending row younger than this is normal in-flight latency, not a
    // problem — only rows older than this are worth an extra Paystack call.
    staleThresholdMinutes: Number(process.env.RECONCILE_STALE_THRESHOLD_MINUTES ?? 10),
  },

  alerts: {
    // Optional: alerting degrades to a logged warning when unset, so this
    // never blocks local dev/test from running.
    slackWebhookUrl: process.env.SLACK_ALERT_WEBHOOK_URL,
  },

  firebase: {
    // Optional, same "degrade to a logged warning" shape as alerts above —
    // Task 19a shipped this backend infra before a real Firebase project
    // existed for this app. Standard service-account triple; PRIVATE_KEY
    // commonly arrives from .env with literal "\n" sequences instead of
    // real newlines, so that's unescaped here once, rather than in every
    // caller.
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  },

  brevo: {
    // Optional, same "degrade to a logged warning" shape as alerts/firebase
    // above — see EmailService's doc comment.
    apiKey: process.env.BREVO_API_KEY,
    senderEmail: process.env.BREVO_SENDER_EMAIL,
    senderName: process.env.BREVO_SENDER_NAME ?? 'RUN-It',
  },

  matching: {
    rebroadcastSeconds: Number(process.env.MATCHING_REBROADCAST_SECONDS ?? 20),
    escalateSeconds: Number(process.env.MATCHING_ESCALATE_SECONDS ?? 120),
  },
});
