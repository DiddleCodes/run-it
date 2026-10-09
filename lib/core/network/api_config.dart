import 'package:flutter/foundation.dart';

/// The production backend.
const productionApiBaseUrl = 'https://api.bridgitcampus.com';

/// The Bridgit backend's base URL. Override with
/// `--dart-define=API_BASE_URL=...`. Without it, a release build talks to
/// production (so a release can never silently ship pointing at a
/// developer's machine) and a debug run talks to the local dev server.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: kReleaseMode ? productionApiBaseUrl : 'http://localhost:3000',
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
const paystackCallbackUrl = '$productionApiBaseUrl/payments/callback';

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
