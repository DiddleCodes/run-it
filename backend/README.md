# RUN-It Payments

Backend for RUN-It's payment surface: a minimal user identity, a real student
wallet, and order-linked escrow settled through Paystack. Everything else
(OTP delivery, KYC storage, job dispatch, chat) stays client-mocked — this
service owns money movement only.

## Architecture decision: no Paystack Split / subaccounts

Order payments are **not** routed through Paystack's instant Split or
subaccount feature. Splits settle automatically on Paystack's normal cycle
regardless of delivery outcome — if an order fails or is disputed after that
settlement, the refund has to come out of the platform's own balance anyway,
which defeats the point of a split.

Instead:

1. The full order amount is collected into the platform's **main** Paystack
   balance at checkout (no subaccount attached to the charge).
2. It's held internally as "escrowed" against that order (`order_escrows`,
   status `held`) — no money has moved anywhere yet.
3. Only once delivery is confirmed does the backend fire real Paystack
   **Transfers** to the restaurant's and runner's registered bank accounts.
   The platform's commission simply never leaves the main balance.
4. If the order is cancelled/disputed before delivery, nothing was ever
   transferred out — refunding the student is a wallet credit, not a
   Paystack call.

## Data model

`prisma/schema.prisma` matches the spec's five tables, with two additions
that turned out to be load-bearing while implementing `/release`:

- `order_escrows.restaurant_user_id` / `runner_user_id` — `/release` takes no
  body (only an internal caller hits it), so it has to look up "the
  restaurant's and runner's payout accounts" from something captured at hold
  time. These are set once, at `/hold`, from the checkout request.
- `order_escrows.restaurant_transfer_status` / `runner_transfer_status` —
  per-leg confirmation state (`pending` / `success` / `failed`), separate
  from the top-level `status`. The top-level `status` flips to `released` as
  soon as both Transfer API calls are successfully *initiated* (per spec);
  these two columns are what the `transfer.success` / `transfer.failed`
  webhook actually reconciles afterward.

Money is always an integer (kobo). Nothing in this service touches a float.

## Commission split

An order has two separate money lines — the **food subtotal** and the
**delivery fee** — and they're never mixed: restaurant commission only ever
touches the food subtotal, and the runner's cut only ever comes out of the
delivery fee.

```
RESTAURANT_COMMISSION_RATE=0.15   # 0-1, applied to food_subtotal only
RUNNER_DELIVERY_FEE_SHARE=0.85    # 0-1, runner's cut of delivery_fee
DEFAULT_DELIVERY_FEE=35000        # kobo (₦350), flat fee, see below
```

These are real business decisions, not implementation details — expect them
to be revisited as the business grows. Current defaults: the platform takes
15% of every order's food subtotal, and keeps 15% of the flat ₦350 delivery
fee (the runner keeps the other 85%, currently ₦297.50 → rounds to ₦298).

**The formula** (`src/order-escrow/commission.util.ts`):

```
platform_fee     = (food_subtotal * RESTAURANT_COMMISSION_RATE)
                    + (delivery_fee * (1 - RUNNER_DELIVERY_FEE_SHARE))
restaurant_share = food_subtotal - (food_subtotal * RESTAURANT_COMMISSION_RATE)
runner_share      = delivery_fee * RUNNER_DELIVERY_FEE_SHARE
order_total       = food_subtotal + delivery_fee   # no separate service fee at launch
```

The commission on the food subtotal is rounded first, so `restaurant_share`
is exact and never touched by rounding. The runner's share is rounded from
the delivery fee; the platform absorbs whatever remainder that rounding
leaves, so the three shares always sum to exactly `order_total` (no kobo
lost or invented).

**Delivery fee today is a flat amount** (`DEFAULT_DELIVERY_FEE`), sent by
the caller as `deliveryFeeKobo` on `/hold` and defaulting to the env value
when omitted. There's no distance-based tiering yet — `computeCommissionShares`
takes the delivery fee as a plain number precisely so that logic can be
added at the call site later without changing the split math itself.

**Per-vendor override**: `vendors.commission_rate_override` (nullable) lets
a specific restaurant be negotiated onto a different commission rate than
the platform default, without a schema change — `hold()` prefers it over
`RESTAURANT_COMMISSION_RATE` whenever it's set. It only ever affects the
restaurant-commission side of the formula; the runner/delivery-fee split is
always the global rate.

## Vendor categories

`vendor_categories` is a controlled vocabulary (`slug` + `label`), not a
hardcoded enum — so ops can add a new category with a plain `INSERT`, no
code deploy, while still preventing `Vendor.category` from fragmenting into
near-duplicates ("Nigerian Food"/"nigerian food"/"Naija Dishes") as more
restaurants sign up. `GET /vendors/categories` (public) lists the current
vocabulary; `POST /vendors/me` validates its `category` field
case-insensitively against either column and always persists the canonical
`label` — a slightly different casing self-heals rather than creating a new
value, and an unrecognized category is rejected with a 400 listing the
valid set. The seed migration
(`prisma/migrations/*_add_vendor_categories`) covers every category value
already in use by a real vendor row plus headroom for growth.

## Idempotency

- **charge.success** (wallet top-ups): `wallet_transactions.reference` is
  unique, created up front as `pending` when `/wallet/fund/initialize` runs.
  The webhook does a single atomic `UPDATE ... WHERE reference = $1 AND
  status = 'pending'` inside a DB transaction, then increments the wallet
  balance *only if that update actually matched a row*. A redelivered event
  matches zero rows the second time — no double credit, no lock needed.
- **transfer.success / transfer.failed**: same pattern, gated on
  `restaurant_transfer_status = 'pending'` / `runner_transfer_status =
  'pending'` so a repeat delivery is a no-op.
- **Redis** (`src/redis/redis.service.ts`) adds a fast-path dedupe cache on
  top of this, keyed by `event:reference`. It is deliberately *not* the
  source of truth — the key is only written *after* the database work
  commits, so a crash between "processed" and "cached" just falls through to
  the (still-idempotent) database path on the next delivery. It exists
  purely to skip the round trip on genuine repeat deliveries.
- Webhook routing itself is metadata-keyed: a `charge.success` event is only
  treated as a wallet top-up if `data.metadata.purpose === 'wallet_topup'`
  (set by this service at `/wallet/fund/initialize`), the same pattern used
  to route by metadata in production Paystack integrations. Anything else is
  logged and ignored rather than assumed to be a top-up.

## Auth model

- All wallet/escrow endpoints require a JWT (`Authorization: Bearer <token>`)
  signed with `JWT_SECRET` — the same secret the mobile OTP flow and the
  dashboard's password login both sign with.
- **Suspension is enforced per-request, not just at login** (Task 17): a
  `User.suspendedAt` account is rejected both at fresh sign-in (OTP verify,
  dashboard login) *and* on every subsequent authenticated request from an
  already-issued token — `JwtStrategy.validate()` (every
  `JwtAuthGuard`-protected route) and `AdminGuard` both do a real DB lookup
  by the token's `sub` before letting the request through
  (`src/auth/session-validity.util.ts`). There's still no session store to
  literally revoke a JWT, but this makes the practical difference moot: the
  very next real request after a suspension gets a 401 (`"Your session has
  expired. Please sign in again."`, deliberately as generic as the
  suspended-login rejection below), regardless of how much of the token's
  lifetime is left. One extra indexed lookup per authenticated request.
- `SelfOrAdminGuard` enforces that the caller's `sub` matches the `userId` /
  `studentUserId` in the request (or that the caller's role is `admin`) —
  this is "proof of identity for the relevant user_id."
- `/orders/:orderId/escrow/release` and `/refund` use `EscrowPartyGuard`
  (Task 8d): callable by presenting the `INTERNAL_SERVICE_API_KEY` shared
  secret via the `x-internal-api-key` header, a JWT whose `role` is `admin`
  or `internal_service`, **or** a normal user JWT whose `sub` matches the
  specific party that order's escrow is scoped to for that route — the
  assigned runner for `/release` (they trigger it themselves by scanning the
  delivery-confirmation code), the ordering student for `/refund` (they
  trigger it themselves by cancelling). This is what lets the Flutter app
  call these two routes directly with the caller's own session token instead
  of shipping the internal shared secret inside the client — see the guard's
  own doc comment for the tracked production-hardening follow-up.
- `POST /auth/dev-token` mints a JWT for a given `userId`/`role` (caller
  chooses both — no suspension check, no ownership check) and
  **self-disables when `NODE_ENV=production`**, enforced by `DevOnlyGuard`
  (`src/common/guards/dev-only.guard.ts`). It exists only so this service
  can be exercised end-to-end (Postman collection, local testing) without
  going through the real OTP flow below. It's no longer the only bridge
  student/runner accounts have to a real session — see the next section.
- `POST /users` is still unauthenticated (used by anything that needs a
  bare identity row outside the OTP flow, e.g. `DemoIdentityService`'s
  fixed demo restaurant/runner in the Flutter client) — real student/
  runner sign-in no longer goes through it at all; `POST /auth/otp/verify`
  finds-or-creates its own `User` row internally.

### Mobile auth (OTP)

Student/runner accounts authenticate via a real, backend-verified OTP pair
(Task 17) — no client-side "any 6-digit code succeeds" shortcut and no
dev-token bridge in the loop for a real sign-in anymore.

- `POST /auth/otp/request` — `{ contact }` (email or phone). Generates a
  6-digit code, stores only its SHA-256 hash with a 10-minute expiry
  (`otp_verifications`, same shape as `password_reset_tokens`), and
  invalidates any still-live code already issued for that contact. Always
  returns the same generic message regardless of whether the contact
  matches an existing account — same no-enumeration convention as
  `/auth/forgot-password`. No SMS/email provider is wired up yet — the
  code is **logged via `Logger`**, not sent; search the server log for
  `OTP requested for` when testing this locally.
- `POST /auth/otp/verify` — `{ contact, code, accountType, name? }`
  (`accountType` must be `student` or `runner`). Rejects a wrong, expired,
  or already-consumed code, **and a suspended account**, with the exact
  same generic message (`"Invalid or expired code"`) — a suspended account
  must never be distinguishable from a wrong code by the response alone,
  mirroring the dashboard login's own convention. On success: finds the
  existing `User` for that contact, or creates one (plus a zero-balance
  `Wallet` for a student) on a first-time verify, then issues the same
  `JWT_SECRET`-signed JWT shape every other login here does.
- Both routes are rate-limited (`@Throttle`) the same way `/auth/login` and
  `/auth/forgot-password` are.

### Web dashboard auth (email + password)

Student/runner accounts authenticate on the mobile app via OTP, as above.
Restaurant and admin accounts additionally get a real email+password login
for the web dashboard (Task 13a) — this is a second, independent credential
type on the same `User` row, not a replacement for OTP.

- `POST /auth/login` — `{ email, password }` → `{ accessToken, user }`.
  Validates against `User.password` (bcrypt hash); only `accountType`
  `restaurant` or `admin` can ever succeed here — student/runner accounts
  have no password set and are rejected the same generic way a wrong
  password would be. Issues the same `JWT_SECRET`-signed JWT shape used
  everywhere else in this API (`{ sub, accountType, role }`), with
  `role: 'admin'` for admin accounts and `role: 'user'` for restaurant
  accounts — so it composes with `SelfOrAdminGuard` / `InternalOrAdminGuard`
  without any special-casing.
- `GET /auth/me` — `JwtAuthGuard`-protected; returns the caller's own
  profile. What the dashboard uses to hydrate its session/top bar.
- `POST /auth/forgot-password` — `{ email }`, always returns the same
  generic "if that email is registered…" message regardless of whether it
  matched anything, so this endpoint can't be used to enumerate accounts. If
  it did match a restaurant/admin account, a single-use reset token
  (30-minute expiry, only its SHA-256 hash stored) is created and the reset
  link is **logged via `Logger`, not emailed** — no email provider is wired
  up yet. Search the server log for `Reset link:` when testing this locally.
- `POST /auth/reset-password` — `{ token, newPassword }`. Rejects an
  unknown/expired/already-used token.
- Rate limiting: `/auth/login` and `/auth/forgot-password` carry a tighter
  `@Throttle` than the app-wide default, on top of the generic
  invalid-credentials response, as basic brute-force/enumeration resistance.
- Dev seed: `npm run prisma:seed` creates `admin@runit.dev` and
  `restaurant@runit.dev`, both with password `RunIt-Dev-2026!` — see
  `prisma/seed.ts`. Dev-only; never run against a production database.

## Running it

### Requirites

- Node 18+
- PostgreSQL and Redis (`docker-compose.yml` is provided for both)
- A Paystack test secret/public key pair

### Setup

```bash
cp .env.example .env   # fill in real Paystack test keys, a long JWT_SECRET, etc.
npm install
docker compose up -d   # postgres + redis, or point DATABASE_URL/REDIS_URL at your own
npm run prisma:migrate # applies prisma/migrations, generates the client
npm run start:dev
```

Env vars (`.env.example`):

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Postgres connection string |
| `REDIS_URL` | Redis connection string |
| `PAYSTACK_SECRET_KEY` | Server-side only. Never shipped to the client. |
| `PAYSTACK_PUBLIC_KEY` | Returned to clients that need it for inline Paystack widgets |
| `JWT_SECRET` | Must match whatever signs tokens from the app's real auth flow |
| `INTERNAL_SERVICE_API_KEY` | Shared secret for the delivery-confirmation flow calling `/release` and `/refund` |
| `RESTAURANT_COMMISSION_RATE` / `RUNNER_DELIVERY_FEE_SHARE` / `DEFAULT_DELIVERY_FEE` | Commission/delivery-fee split — see "Commission split" above |
| `AWS_REGION` / `S3_UPLOADS_BUCKET` / `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | S3 credentials/bucket for `POST /uploads/presign` |
| `S3_PUBLIC_BASE_URL` | Optional CDN/custom domain fronting the bucket; falls back to the bucket's default virtual-hosted-style URL |

### Tests

```bash
npm test
```

73 unit tests covering:

- **Webhook idempotency** (`test/webhooks.service.spec.ts`) — duplicate
  `charge.success` delivery credits the wallet exactly once; metadata-based
  routing; the Redis fast path; transfer-event reconciliation; the two
  reconciliation entry points (`applyVerifiedChargeSuccess`,
  `applyVerifiedTransferResult`, `markChargeFailed`) called directly,
  independent of any webhook delivery.
- **Webhook fast-ack + queue** (`test/webhooks.controller.spec.ts`) —
  rejects an invalid signature before touching the queue; enqueues and
  returns `200` regardless of how slow a worker would be; propagates a
  genuinely broken queue rather than pretending the event was accepted.
- **Webhook worker retry/alerting** (`test/webhooks.processor.spec.ts`) —
  rethrows a processing failure so BullMQ retries rather than swallowing
  it; alerts only once retries are exhausted, not on every attempt.
- **Webhook source-IP allowlist** (`test/paystack-webhook-ip.guard.spec.ts`)
  — enforced only in production; explicit empty-allowlist escape hatch.
- **Reconciliation sweep** (`test/reconciliation.service.spec.ts`) — a
  manually-inserted stale-pending wallet_transaction and a stale
  escrow transfer leg, each resolved (success/failed/reversed) or alerted
  on (still-pending, or the verify call itself failing) correctly.
- **Escrow lifecycle** (`test/order-escrow.service.spec.ts`) — hold computes
  the configured split correctly and debits atomically; release calls the
  Paystack Transfer API with the exact restaurant/runner share amounts, is
  safely retriable per-leg, and atomically flips escrow+order status
  together; refund credits the wallet back and asserts `initiateTransfer`
  is **never** called; a `P2002` unique-constraint race on
  `order_escrows.order_id` is converted to a clean `409`, not a raw `500`
  (an unrelated DB error is not swallowed the same way).
- **DB-level duplicate-hold rejection, against a real Postgres**
  (`test/order-escrow.db-constraint.integration.spec.ts`) — proves the
  constraint itself, not application logic, is what prevents a duplicate.
  Skipped by default; run explicitly with `RUN_DB_INTEGRATION_TESTS=1 npx
  jest order-escrow.db-constraint`.
- **Payout account verification** (`test/payout-accounts.service.spec.ts`) —
  an unresolvable bank account is rejected before anything is saved or a
  Transfer Recipient is created.
- **Commission split math** (`test/commission.util.spec.ts`).
- **Vendor/menu ownership** (`test/vendors.service.spec.ts`) — a vendor can't
  edit, delete, or toggle availability on another vendor's menu item;
  metrics aggregation asserted against a seeded set of real orders (exact
  revenue/count numbers, not just "doesn't crash"), excluding cancelled
  orders.
- **Presigned uploads** (`test/uploads.service.spec.ts`) — correct S3 key
  namespacing per purpose and content-type-to-extension mapping.
- **Ratings** (`test/ratings.service.spec.ts`) — rejects rating someone
  else's order, an order that isn't `delivered` yet, and a duplicate rating;
  correctly recalculates the runner's cached average/count.

These are all pure unit tests against mocked Prisma/Paystack/Redis/S3/BullMQ
(see `test/support/mocks.ts` and `test/support/nestjs-bullmq.mock.js`) — no
database required to run `npm test` (the one test that genuinely needs a
real Postgres instance is opt-in only, see above).

The full request pipeline (real Postgres, real Redis, real HTTP, real
HMAC-signed webhook delivery, live calls to `api.paystack.co`) was manually
verified while building this: fund→webhook→balance credited exactly once
across two identical deliveries; hold→balance debited for food subtotal +
delivery fee with the correct commission/delivery-fee split (including a
per-vendor commission override); hold→refund→balance restored, with a second refund attempt
correctly rejected (409); hold→release correctly rejected without a payout
account on file (422), and correctly reaching Paystack's Transfer endpoint
with the right amounts once one exists.

Task 9's endpoints were manually verified the same way against a real local
Postgres/Redis instance: vendor profile → menu item → public menu fetch;
hold with real `vendorId`/`items` → confirmed the `orders`/`order_items` rows
in the database directly; a rival vendor's edit/delete attempts on another
vendor's menu item both correctly rejected (403) over real HTTP, not just in
a unit test; rating → duplicate rejected (409) → rating summary reflects the
new average; metrics correctly aggregated the real seeded order. `/release`
was exercised up to the same Paystack-payout-account boundary already
documented above (422 without one on file) — reaching `delivered` for real
requires real Paystack test credentials this sandbox doesn't have, so the
order was flipped to `delivered` directly in Postgres to exercise the rating
flow honestly (this only affects the manual verification step; the
`/release` → `delivered` wiring itself is unit-tested).

Task 9b's queue/reconciliation/alerting layer was also manually verified
live, real BullMQ worker included (not mocked): a real HMAC-signed
`charge.success` webhook returned `200` in ~20ms and the wallet was credited
moments later by the async worker; the real-DB unique-constraint test
(above) passed against live Postgres; `POST /reconciliation/run` correctly
found and resolved a genuinely-stale pending wallet_transaction, and — with
`SLACK_ALERT_WEBHOOK_URL` pointed at a local listener — actually delivered a
well-formed alert payload when the (placeholder-keyed) Paystack verify call
failed, exactly as it would in production. The only thing not exercisable
here is a real Paystack verify call succeeding, same "no real Paystack test
credentials in this sandbox" limitation as everywhere else in this README.

## API summary

| Endpoint | Auth | Notes |
|---|---|---|
| `POST /users` | none | minimal identity bootstrap; creates a wallet too if `accountType: student` |
| `POST /auth/dev-token` | none (disabled in prod) | testing only |
| `POST /auth/login` | none (credentials in body) | web dashboard only; restaurant/admin accounts |
| `GET /auth/me` | any authenticated user | current caller's profile |
| `POST /auth/forgot-password` | none | always generic response; logs reset link server-side |
| `POST /auth/reset-password` | none (token in body) | single-use, 30-minute-expiry token |
| `POST /wallet/fund/initialize` | self/admin | returns Paystack `authorization_url` |
| `GET /wallet/:userId/balance` | self/admin | |
| `GET /wallet/:userId/transactions` | self/admin | paginated via `?take=&skip=` |
| `GET /payout-accounts/banks` | any authenticated user | proxies Paystack's List Banks (24h in-memory cache); not user-scoped, so it's exempt from the self/admin check the rest of this controller uses |
| `POST /payout-accounts` | self/admin | verifies via Paystack resolve-account, then creates a Transfer Recipient |
| `GET /payout-accounts/:userId` | self/admin | |
| `POST /orders/:orderId/escrow/hold` | self (student) /admin | debits wallet, creates escrow `held`, and — since Task 9 — also creates the `orders`/`order_items` rows for that order (see below). `runnerUserId` is optional (Task 21a) — omit it for the real broadcast-and-claim flow |
| `POST /orders/:orderId/escrow/claim` | any authenticated runner | Task 21a — atomic first-to-claim-wins; `409 {code: 'ORDER_ALREADY_CLAIMED'}` for the loser. See "Runner matching" below |
| `POST /orders/:orderId/escrow/release` | assigned runner (self) / internal service key / admin | Transfers to restaurant + runner, escrow `released`, order → `delivered` |
| `POST /orders/:orderId/escrow/refund` | ordering student (self) / internal service key / admin | wallet credit only, escrow `refunded`, order → `cancelled` |
| `POST /webhooks/paystack` | Paystack signature (+ source IP in prod) | verifies + enqueues; `WebhooksProcessor` does the actual DB work async — see "Task 9b" |
| `POST /reconciliation/run` | internal service key / admin | manually triggers the stale-pending sweep — see RUNBOOK.md |
| `POST /vendors/me` | restaurant (self) /admin | create/update the caller's own vendor profile |
| `GET /vendors/:id/menu` | none | public menu browsing |
| `POST /vendors/me/menu-items` | restaurant (self) /admin | |
| `PATCH /vendors/me/menu-items/:id` | restaurant (self) /admin, must own the item | |
| `DELETE /vendors/me/menu-items/:id` | restaurant (self) /admin, must own the item | |
| `PATCH /vendors/me/menu-items/:id/availability` | restaurant (self) /admin, must own the item | quick sold-out toggle |
| `GET /vendors/me/metrics` | restaurant (self) /admin | most-ordered items, revenue, over `?from=&to=` (default last 30 days); computed from real `orders`/`order_items`, cancelled orders excluded |
| `POST /uploads/presign` | any authenticated user | presigned S3 PUT URL + final public URL for a menu-item photo or vendor logo |
| `POST /orders/:orderId/rating` | ordering student (self) | rejects if the order isn't `delivered` yet, or already rated |
| `GET /runners/:id/rating-summary` | none | cached `average_rating`/`rating_count`, recalculated on every new rating |

## Task 9: vendors, menu, uploads, order items, ratings

- **The `orders`/`order_items` tables are populated by `/escrow/hold`
  itself** (`OrderEscrowService.hold()`), not a separate order-creation
  endpoint — that keeps `/hold`'s existing single-request-per-order contract
  intact instead of requiring the already-shipped Flutter client to make a
  second call it doesn't currently make. `vendorId` and `items` are new,
  **optional** fields on `HoldEscrowDto`: omitting them (as the current
  Flutter client does) still creates a minimal `Order` row, auto-provisioning
  a placeholder `Vendor` from `restaurantUserId` if that restaurant has never
  called `POST /vendors/me`. `order_escrows.order_id` is a hard foreign key
  into `orders.id` — safe only because `hold()` always creates the `Order`
  row itself, in the same transaction, before creating the escrow row.
- **Order status** only ever takes the three values this backend actually
  drives: `placed` (at hold), `delivered` (at release), `cancelled` (at
  refund). Runner-assignment/pickup tracking belongs to the not-yet-built
  runner-matching module — see the tracked follow-ups below.
- **Ratings** are recalculated into `users.average_rating` /
  `users.rating_count` on every write (application code, not a DB trigger),
  matching this codebase's existing reconciliation style (see
  `webhooks.service.ts`).
- **Uploads**: `POST /uploads/presign` generates a SigV4-signed S3 `PutObject`
  URL entirely offline (no network call to AWS at presign time) — the actual
  file bytes go straight from the client to S3 and never pass through this
  backend. `contentLengthBytes` is validated before issuing the URL, but
  can't be cryptographically enforced on a presigned **PUT** (only a
  presigned **POST** policy supports a content-length-range condition) —
  acceptable here since every uploader is an authenticated vendor, not an
  anonymous public client.

### Tracked follow-ups (do not ship to production as-is)

- **`OrderEscrowService.resolveVendorId()`'s auto-provisioned placeholder
  Vendor** (`businessName: 'Unnamed vendor'`) is a stand-in for restaurants
  that predate the vendor-profile feature. Once every restaurant onboards
  through `POST /vendors/me` for real, this fallback should become
  unreachable in practice; consider removing it (or turning it into a hard
  error) once that's true.
- **Order-lifecycle granularity**: `OrderStatus` only tracks
  `placed`/`delivered`/`cancelled` because nothing else in this backend sets
  intermediate states yet. A future runner-matching/dispatch module should
  extend this rather than re-deriving order state from escrow status.

See `postman/RUN-It-Payments.postman_collection.json` for a runnable
walkthrough covering fund/initialize, the full hold→release cycle,
hold→refund, and (folder 6) vendor/menu CRUD, a presigned upload, and the
rating flow, including a pre-request script that HMAC-signs the mock webhook
body so it can be fired straight at your local server.

## Task 9b: production hardening

**See `RUNBOOK.md`** for what to do when an alert actually fires — this
section is the architecture; that one is the on-call playbook.

### Webhook queue + fast ack

`POST /webhooks/paystack` now only does two cheap, synchronous checks
(source IP in production, HMAC signature) and then enqueues the event onto
a BullMQ queue (`paystack-webhooks`, Redis-backed via a dedicated
`ioredis` connection — see `AppModule`), returning `200` immediately. The
actual DB work — crediting wallets, updating transfer leg statuses — happens
in `WebhooksProcessor`, off the request/response cycle entirely. A slow or
temporarily-broken database can no longer make this endpoint time out or
trigger a Paystack retry storm.

`WebhooksProcessor.process()` deliberately doesn't catch its own errors —
letting them throw is what tells BullMQ to retry (5 attempts, exponential
backoff starting at 5s). It's safe to retry because
`WebhooksService.applyPaystackEvent()` is idempotent (same atomic
conditional-update pattern as before, see "Idempotency" above) regardless of
how many times a given event is dequeued. Only once all 5 attempts are
exhausted does `WebhooksProcessor`'s `@OnWorkerEvent('failed')` hook fire a
Slack alert — a job still mid-retry is not alert-worthy yet.

### Reconciliation

`ReconciliationService` runs on a schedule (`RECONCILE_INTERVAL_MINUTES`,
default 5 — registered dynamically via `SchedulerRegistry` rather than a
static `@Cron()` string, so the interval is genuinely config-driven) and is
also triggerable on demand via `POST /reconciliation/run` (internal key or
admin JWT). On each run it finds `wallet_transactions`/`order_escrows` rows
stuck `pending` past `RECONCILE_STALE_THRESHOLD_MINUTES` (default 10),
calls Paystack's verify-transaction / verify-transfer endpoints, and applies
the real answer through the *exact same* idempotent methods the webhooks
themselves use (`WebhooksService.applyVerifiedChargeSuccess` /
`applyVerifiedTransferResult` — refactored out specifically so there is only
one implementation of "credit a wallet for a confirmed charge" or "settle a
transfer leg" in the whole codebase, not two that could drift apart). This
is genuinely self-healing for a lost webhook, not just an alert asking a
human to go look.

### Database-level idempotency

`wallet_transactions.reference` and `order_escrows.order_id` were already
`@unique` (Task 8b) — real Postgres unique constraints, not just an
application-level check. What Task 9b added: `OrderEscrowService.hold()`
now catches the `P2002` a losing concurrent request's `orderEscrow.create()`
throws when it races against the constraint, and converts it into the same
clean `409 Conflict` the early `findUnique` pre-check gives everyone else —
so a genuine race (two concurrent hold requests for the same order, both
passing the pre-check) fails safely instead of surfacing a raw `500`. See
`test/order-escrow.db-constraint.integration.spec.ts` for a real-Postgres
proof that the constraint itself — not the pre-check — is what actually
prevents the duplicate (run explicitly: `RUN_DB_INTEGRATION_TESTS=1 npx
jest order-escrow.db-constraint`; skipped by default so `npm test` still
needs no live database).

### Transactional integrity — and one deliberate deviation

`hold()` and `refund()` are each a single `$transaction` — already true
before Task 9b, unchanged. `release()`'s **final DB status flip**
(`order_escrows.status → released` + `orders.status → delivered`) is now
also one `$transaction`, so those two can never disagree.

What `release()` is **not** wrapped in: one transaction spanning its two
Paystack Transfer API calls. This is intentional, not an oversight — those
are real network calls with real-world side effects (money actually moves).
A DB transaction that rolled back *after* a transfer had already been
initiated would leave Paystack's records and ours permanently disagreeing,
with no way to undo the transfer. Instead, each leg's
Paystack-call-then-DB-write is already atomic on its own (a single
`update`) and safely retriable per-leg — `release()` only re-attempts a leg
that doesn't already have a transfer reference recorded, so calling it again
after a partial failure can't double-pay a leg that already went out. That
per-leg idempotency (backed up by reconciliation, above) is what makes this
safe — not artificial atomicity across an external call. See `release()`'s
own code comment and RUNBOOK.md.

### Alerting

`AlertsService` posts to a Slack incoming webhook
(`SLACK_ALERT_WEBHOOK_URL`) for: a webhook job that exhausted all retries, a
reconciliation-resolved failure/reversal, a reconciliation verify call that
itself errored, and something still stuck past the threshold with no
resolution. Deliberately never throws — a broken Slack URL degrades to a
logged warning rather than turning alerting itself into a new failure mode.

### Defense in depth

- `PaystackWebhookIpGuard` checks the request's source IP against
  `PAYSTACK_WEBHOOK_IP_ALLOWLIST` (defaults to Paystack's published webhook
  IPs) as a second factor alongside HMAC signature verification —
  **production only** (mirrors `/auth/dev-token`'s inverse convention of
  disabling itself only in production); local/staging webhook testing
  (including this collection's own "Simulate Webhook" requests) relies on
  signature verification alone, same as before.
- `POST /webhooks/paystack` is rate-limited to 60 requests/minute per source
  IP (`@nestjs/throttler`), configured only on this route — nothing else in
  this backend rate-limits by IP the same way.

## Task 21a: runner matching (broadcast-and-claim)

Replaces the old client-side "resolve one fixed demo runner and bake it
into the order at checkout" stopgap (`DemoIdentityService`, Flutter-side —
already broken in production once Task 17 hard-disabled `/auth/dev-token`
outside non-production) with a real, backend-driven flow: an order can now
be held with **no runner attached**, gets broadcast to every connected
runner once the restaurant accepts it, and the first runner to claim it
wins — atomically.

- **Nullable runner at hold time**: `OrderEscrow.runnerUserId` and
  `HoldEscrowDto.runnerUserId` are both optional now. `Order.runnerUserId`
  (already nullable) and `OrderEscrow.runnerUserId` are kept in sync by
  every writer of either — `OrderEscrow.runnerUserId` is the
  authorization/payout source of truth (`EscrowPartyGuard`, `release()`);
  `Order.runnerUserId` is a denormalized copy for the Order side's own
  ownership checks.
- **The broadcast trigger**: fires from `VendorsService.advanceOrderStatus`
  when a restaurant moves an order to `preparing` — not at hold/placement
  time, since the restaurant hasn't even seen the order yet at that point.
  Only fires for orders held with no runner attached (the not-yet-updated
  Flutter client still resolves one up front — see Task 21b).
- **The claim**: `POST /orders/:orderId/escrow/claim`, any authenticated
  runner. Correctness lives entirely in one conditional update — `WHERE
  runner_user_id IS NULL` — the same pattern this file already uses for the
  wallet debit in `hold()` and the status flip in `refund()`. A losing
  claim gets a distinct `409 {code: 'ORDER_ALREADY_CLAIMED'}`, not a
  generic conflict.
- **The broadcast channel**: `RunnerDispatchGateway`, a new Socket.IO
  namespace (`/runner-dispatch`), separate from `NotificationsGateway`'s
  restaurant-only `/restaurant-orders` — that gateway's own doc comment had
  already anticipated this as a distinct future namespace rather than an
  extension of itself. Same JWT-at-handshake auth shape; the connection
  guard checks `accountType === 'runner'` instead of looking up a `Vendor`
  row. Every connected runner joins one shared room (`runners:online`) —
  **there is no campus concept anywhere in this backend** (nothing
  persists one; campus enforcement is explicitly out of scope for this
  task), so campus-scoped rooms aren't implemented yet. Swapping in real
  `campus:<id>` rooms later only touches this gateway's room-join call.
- **Re-broadcast + escalation**: `MatchingService` schedules two delayed
  BullMQ jobs when it broadcasts (`MATCHING_REBROADCAST_SECONDS`, default
  20; `MATCHING_ESCALATE_SECONDS`, default 120) — the same delayed-job
  mechanism already used for FCM pushes and webhook processing, not a new
  scheduling primitive. Each handler re-checks the order fresh from
  Postgres before acting (still unclaimed? still in a claimable status?)
  rather than trusting stale job data. A successful claim cancels both
  jobs by their deterministic ids (`rebroadcast-<orderId>`,
  `escalate-<orderId>`).
- **Escalation target**: reuses the existing `Dispute` model/pattern
  (`upsert` on `orderId`, same as the delivery-proof-review path), with a
  distinct reason string ("No runner claimed this order within the
  matching window"). `Dispute.orderId` is `@unique`, so if an order both
  escalates *and* later needs a delivery-proof dispute, the second
  `upsert` leaves the first `reason` in place rather than overwriting it —
  in practice these are temporally disjoint (escalation only fires before
  a runner is ever attached; delivery-proof disputes only fire after
  pickup), but this is a pre-existing limitation of `Dispute` carrying one
  reason per order, not something this task changes.
- **Known gap, not fixed here**: none of this applies to runner (phone)
  contacts differently than student ones — matching is account-type
  agnostic — but there's still no backend concept of a runner's campus at
  all, so "broadcast to available runners" today means literally every
  connected runner, everywhere.
  the API is meaningfully rate-limited by this.
