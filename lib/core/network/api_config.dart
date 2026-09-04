/// The RUN-It payments backend's base URL (Task 8b's NestJS service).
/// Override at build/run time with `--dart-define=API_BASE_URL=...` for a
/// staging/production backend; defaults to the local dev server.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

/// Paystack's *public* key only — the secret key never leaves the backend
/// (see `PayoutRepository`/`WalletRepository`, which always route through
/// our own server). This is unused on iOS/Android with the
/// authorization-URL checkout flow `flutter_paystack_plus` uses here (the
/// package only needs it for its web target) — kept wired through so a
/// future web build has it, and so nothing client-side ever needs the
/// secret key by construction.
const paystackPublicKey = String.fromEnvironment(
  'PAYSTACK_PUBLIC_KEY',
  defaultValue: 'pk_test_placeholder',
);

/// Must match the backend's `PAYSTACK_CALLBACK_URL` (`.env.example`) — see
/// that config value's own doc comment for why the two have to agree.
const paystackCallbackUrl = 'https://runit.app/payments/callback';

/// Task 31: a Sentry DSN is publish-only (safe to ship in the compiled
/// app), same trust level as the API base URL above — unlike the backend's
/// Paystack secret key, this is not a credential that needs to stay out of
/// source. Empty disables crash reporting entirely (see
/// crash_reporting.dart) — override with
/// `--dart-define=SENTRY_DSN=...` for a different environment/project.
const sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue:
      'https://9fd415708b1747fb96bc3b23d726ef58@o4512024018354176.ingest.de.sentry.io/4512024082055248',
);
