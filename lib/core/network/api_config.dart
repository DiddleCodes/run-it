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
