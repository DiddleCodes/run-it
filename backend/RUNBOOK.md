# RUN-It Payments — Runbook

What to do when a payments alert fires. This backend moves real money
(wallet top-ups, escrow holds, restaurant/runner payouts) — when something
looks wrong, verify against Paystack directly before assuming the database
is right, and never manually credit/debit a wallet without understanding
why the automated path didn't.

## How alerts reach you

`AlertsService` posts to `SLACK_ALERT_WEBHOOK_URL` (a Slack incoming
webhook). If that env var isn't set, alerts degrade to a `WARN`-level log
line prefixed `[ALERT, no SLACK_ALERT_WEBHOOK_URL configured]` — check
application logs if Slack has gone quiet and you suspect this.

Every alert is one of three kinds. Each names the row(s) involved directly
in its message/context, so you can jump straight to "Inspect a stuck
escrow" or "Inspect a stuck wallet top-up" below.

1. **Webhook processing permanently failed** (`WebhooksProcessor`) — a
   queued Paystack webhook event failed all 5 retry attempts (exponential
   backoff, ~5s/10s/20s/40s/80s). The job's full `data` (the original
   Paystack event payload) is in the alert context.
2. **Reconciliation resolved something as failed/abandoned/reversed, or
   couldn't verify at all** (`ReconciliationService`) — the periodic sweep
   found a stale `pending` row, called Paystack to check its real status,
   and either got a bad-news answer or the verify call itself errored.
3. **Something is still stuck pending after the threshold, with no
   resolution** (`ReconciliationService`) — Paystack itself still says
   `pending`/similar. Nothing was wrong with our side; Paystack just hasn't
   settled it yet. Usually resolves itself on a later sweep — but if it
   persists across several sweeps, treat it as a Paystack-side incident.

## Quick reference: inspecting things directly

```sql
-- A specific order's escrow state
SELECT * FROM order_escrows WHERE order_id = '<orderId>';

-- All escrows with a leg still pending past 10 minutes since release
SELECT id, order_id, restaurant_transfer_status, runner_transfer_status,
       restaurant_transfer_reference, runner_transfer_reference, released_at
FROM order_escrows
WHERE status = 'released'
  AND released_at < now() - interval '10 minutes'
  AND (restaurant_transfer_status = 'pending' OR runner_transfer_status = 'pending');

-- All wallet top-ups still pending past 10 minutes
SELECT id, reference, amount, wallet_id, created_at
FROM wallet_transactions
WHERE status = 'pending' AND created_at < now() - interval '10 minutes';
```

**Timezone caution**: `created_at`/`released_at` are `TIMESTAMP` columns
(no timezone). The application (Prisma/node-postgres) always reads and
writes them as UTC consistently, so normal app behavior is correct
regardless of the Postgres server's own `timezone` setting. But if you ever
write to these columns by hand via `psql` — e.g. `now() - interval '20
minutes'` — Postgres evaluates `now()` in the **session's** timezone
(`SHOW timezone;`), not necessarily UTC, and the naive value that gets
stored will then be silently misread by the app as being adrift by however
many hours that session's zone is offset from UTC. If you must hand-edit a
timestamp, use `(now() AT TIME ZONE 'UTC') - interval '20 minutes'`, or
just do it from a Node/Prisma script (`new Date(...)`) instead of raw SQL.

## How to manually trigger reconciliation

Don't wait for the next scheduled sweep (every `RECONCILE_INTERVAL_MINUTES`,
default 5) — trigger it directly:

```bash
curl -X POST https://<host>/reconciliation/run \
  -H "x-internal-api-key: $INTERNAL_SERVICE_API_KEY"
```

(An admin JWT also works: `-H "authorization: Bearer <admin-token>"`.)

Response shape: `{ "walletChecked": <n>, "transferLegsChecked": <n> }` — how
many stale rows it looked at, not how many it changed. Check application
logs (`ReconciliationService`) for the actual per-row outcome, or re-query
the row directly.

This calls the exact same code path as the scheduled sweep
(`ReconciliationService.runReconciliation()`) — safe to call repeatedly;
every row it touches is resolved through the same atomic
`updateMany({ where: { status: 'pending' } })` pattern the webhooks
themselves use, so re-running it never double-applies anything.

## How to check a transfer's real Paystack status

Don't trust `order_escrows.restaurant_transfer_status` /
`runner_transfer_status` blindly if you suspect a lost webhook — ask
Paystack directly:

```bash
curl https://api.paystack.co/transfer/verify/<reference> \
  -H "Authorization: Bearer $PAYSTACK_SECRET_KEY"
```

`<reference>` is `escrow_<escrowId>_restaurant` or `escrow_<escrowId>_runner`
(also stored verbatim in `order_escrows.restaurant_transfer_reference` /
`runner_transfer_reference`). The `data.status` field in the response is
the source of truth — `success`, `failed`, `reversed`, or `pending`.

Same idea for a wallet top-up, by charge reference instead of transfer
reference:

```bash
curl https://api.paystack.co/transaction/verify/<reference> \
  -H "Authorization: Bearer $PAYSTACK_SECRET_KEY"
```

If Paystack's answer disagrees with what's in our database, don't hand-edit
the row — run reconciliation (above); it calls this exact endpoint and
applies the result through the same idempotent path the webhook would have
used.

## Playbook by alert type

### "Webhook processing permanently failed"

1. Read the alert's `data` field — it's the raw Paystack event payload
   (`event`, `data.reference`, etc.).
2. Check what actually broke: `docker logs`/application logs around the job
   ID for the underlying error on each of its 5 attempts.
3. If the underlying cause was transient (DB was down, deploy in progress)
   and has since resolved: verify by reference using the endpoints above,
   then either re-deliver the webhook from Paystack's dashboard (Developers
   → Webhooks → Events → Retry), or just run manual reconciliation — it'll
   pick up the same row if it's still `pending`.
4. If the cause was a real bug (e.g. a new Paystack event shape our code
   doesn't handle): the event is not lost — it's sitting in the
   `paystack-webhooks` BullMQ queue's failed set (`removeOnFail: 5000`, so
   the last 5000 failed jobs are kept). Fix the bug, then requeue it rather
   than re-deriving the payload from scratch.

### "Resolved as failed/abandoned/reversed via reconciliation"

This means Paystack itself confirmed the bad outcome — this is not a lost
webhook, the underlying charge/transfer genuinely didn't succeed.

- **Wallet top-up abandoned/failed**: the student's money was never
  actually collected. Nothing to reverse — `wallet_transactions.status` is
  now `failed`, wallet balance was never touched. If the student disputes
  this, check the reference on Paystack's dashboard directly.
- **Transfer failed/reversed**: the restaurant/runner did not receive that
  leg's payout. Check `payout_accounts` for that user — a `reversed`
  transfer commonly means the recipient's account details were rejected by
  their bank after initial acceptance. Once the recipient re-verifies their
  payout account (`POST /payout-accounts`), the leg can be retried by
  calling `/orders/:orderId/escrow/release` again — release() only
  re-attempts a leg that doesn't already have a transfer reference
  recorded (see its own code comments), so this is safe to call again even
  though the escrow is already `released`.

### "Still pending past threshold, no resolution"

- If this is the first time you're seeing it for this row: no action
  needed — it commonly resolves on the next sweep or two as Paystack
  finishes settling it.
- If the SAME reference keeps alerting across multiple sweeps (check the
  `ageMinutes` field going up each time): this is a Paystack-side delay,
  not an application bug. Check Paystack's status page. Do not manually
  mark it success/failed — wait for Paystack to actually resolve it, or
  reach out to Paystack support with the reference if it's been hours.

## Operational notes

- **The webhook endpoint itself never fails a Paystack delivery just
  because our database is slow or briefly down** — `POST /webhooks/paystack`
  only verifies the signature (and, in production, the source IP) and
  enqueues the event; the actual DB work happens in `WebhooksProcessor`,
  decoupled via Redis/BullMQ. If you need to confirm the queue itself is
  healthy: check Redis is reachable and that `WebhooksProcessor` is running
  (it's in the same process as the API by default — see `AppModule`).
- **Rate limiting**: the webhook endpoint is throttled to 60 requests/minute
  per source IP (`@nestjs/throttler`). A legitimate burst of real Paystack
  deliveries (e.g. after your own downtime, when Paystack retries a backlog)
  should stay well under this; if you see `429`s from Paystack's own retry
  logs, that limit may need raising for your traffic volume.
- **IP allowlist is production-only**: `PaystackWebhookIpGuard` only
  enforces `PAYSTACK_WEBHOOK_IP_ALLOWLIST` when `NODE_ENV=production`. If a
  production deployment sits behind a reverse proxy/load balancer, Express's
  `trust proxy` setting must be configured to match that infrastructure
  (see `main.ts`) — otherwise every request appears to originate from the
  proxy's own IP and this guard will reject genuine Paystack deliveries. If
  that happens (alerts stop arriving from a proxy migration, or all webhook
  calls suddenly 403), that's the first thing to check — not the allowlist
  itself.
- **A retried hold for the same orderId is always safe.** Two concurrent
  requests, or a client retry after a timeout, cannot create two escrows
  for one order — `order_escrows.order_id` has a real Postgres unique
  constraint, and `OrderEscrowService.hold()` converts the resulting
  constraint violation into a clean `409 Conflict` rather than a `500`. See
  `test/order-escrow.db-constraint.integration.spec.ts` (run explicitly with
  `RUN_DB_INTEGRATION_TESTS=1 npx jest order-escrow.db-constraint` — not
  part of the default `npm test`, since that suite intentionally requires no
  live database) for a live proof against a real Postgres instance.
