# Bridgit Web Dashboard

Restaurant & Admin portal for Bridgit, built with Next.js (App Router) + TypeScript +
Tailwind v4 + shadcn/ui + Framer Motion. This is Task 13a: real auth, real
server-verified role guards, the layout shell, and the shared component set —
foundation only. Full feature screens (Orders tables, Metrics charts, etc. wired to
real backend data) land in Task 13b/13c.

## No role-selection UI — read this first

**The login screen is email + password only.** There is no Restaurant/Admin toggle
anywhere in this app — not visible, not hidden in markup, not in a query param, not
anywhere in the login form's state. `app/login/page.tsx` has no `role` state at all.

Which portal an account lands in is decided **entirely server-side**, from the
`role`/`accountType` claims on the JWT the backend issues after verifying the
password — never from anything the client selects or sends. See "How auth and the
role guard work" below for the full chain. A restaurant account has no way to
discover that an `/admin` portal exists: hitting `/admin/*` directly redirects it to
its own `/restaurant/overview`, never to `/login` (a redirect to `/login` would leak
"there's a distinct protected thing here"), and none of the login page's copy or
metadata mentions "admin" at all.

## Local setup

Requires the backend (`../backend`) running first — this app has no data or auth of
its own, it's a real client of that API.

```bash
# 1. Backend (from repo root)
cd backend
cp .env.example .env   # fill in real values; JWT_SECRET must match this app's
docker compose up -d   # postgres + redis
npm install
npm run prisma:migrate
npm run prisma:seed    # creates admin@runit.dev / restaurant@runit.dev, both RunIt-Dev-2026!
npm run start:dev      # http://localhost:3000

# 2. Dashboard (from repo root, separate terminal)
cd dashboard
cp .env.example .env.local   # BACKEND_URL + JWT_SECRET (must match backend/.env)
npm install
npm run dev             # http://localhost:3001
```

Sign in at <http://localhost:3001/login> with either seeded account:

| Email | Password | Lands on |
|---|---|---|
| `restaurant@runit.dev` | `RunIt-Dev-2026!` | `/restaurant/overview` |
| `admin@runit.dev` | `RunIt-Dev-2026!` | `/admin/overview` |

## How auth and the role guard work

1. **Login** (`app/login/page.tsx`) posts `{ email, password }` to this app's own
   `POST /api/auth/login` route handler — the browser never talks to the NestJS
   backend directly (`BACKEND_URL` is a server-only env var, no `NEXT_PUBLIC_`
   prefix).
2. That route handler forwards the credentials to the backend's
   `POST /auth/login` (see `backend/src/auth/auth.service.ts`), which checks the
   password against a bcrypt hash and — only for `restaurant`/`admin` accounts —
   returns a JWT signed with `JWT_SECRET`, carrying `{ sub, accountType, role }`.
   `role: 'admin'` for admin accounts, `role: 'user'` for restaurant accounts (the
   same `AppRole` scheme the rest of the backend already uses).
3. The route handler sets that JWT as an **httpOnly** cookie
   (`runit_dashboard_session`) and returns only `{ accountType }` in the JSON body —
   enough for the client to pick a redirect target, nothing security-relevant (the
   raw token never reaches client-side JS).
4. **`proxy.ts`** (Next.js's middleware convention, renamed from `middleware.ts` in
   this Next version) runs on every request to a non-public path. It reads the
   httpOnly cookie, verifies the JWT's signature and expiry with `jose`
   (`lib/auth/jwt.ts`, same `JWT_SECRET` as the backend), and checks the verified
   claims:
   - No/invalid session → redirect to `/login`.
   - `/admin/*` and `role !== 'admin'` → redirect to `/restaurant/overview` (never
     to `/login`).
   - `/restaurant/*` and `accountType !== 'restaurant'` → redirect to
     `/admin/overview`.
5. **Defense in depth**: `app/admin/layout.tsx` and `app/restaurant/layout.tsx` are
   server components that independently call `getSession()` and `redirect()` on
   mismatch — a page is never rendered off cookie-presence alone, even if the proxy
   were somehow bypassed for a given path.
6. Nothing about role is ever trusted from the client. The only two places role is
   read are the verified JWT in `proxy.ts`/the layouts, and `GET /auth/me` (used to
   hydrate the TopBar with the real signed-in user's name/email — also
   `JwtAuthGuard`-protected on the backend).

Logout (`POST /api/auth/logout`) just clears the cookie.

## Layout shell & shared components

- `components/layout/` — `AppShell`, `Sidebar` (nav items keyed off the server-read
  role), `TopBar` (real user data from `GET /auth/me`), `PageHeader`.
- `components/shared/` — `DataTable`, `StatCard`, `StatusBadge`, `Modal`/`Drawer`
  (thin wrappers over shadcn `Dialog`/`Sheet`), `ConfirmDialog` (over shadcn
  `AlertDialog`), `EmptyState`, `SkeletonBlock`, plus a `toast` helper over Sonner.
  Rebuilt cleanly against the real session/typed props rather than copy-pasted from
  the Figma Make prototype this app's visual design is based on.
- `/component-library` — full showcase of the above, for design review, with
  illustrative sample data. Development only: it 404s in a production build and
  isn't linked from the nav there.

## Production

`npm run build` then `npm run start` — listens on `$PORT` (Railway sets it), or 3001 when unset; put it behind the host's HTTPS.
Deployed on Railway as the `dashboard` service (project `fabulous-curiosity`).

Railway no longer reads `railway.json` (it rejects pointing a service at one:
"Config as Code is deprecated"), so the same settings are set directly on the
service: **root directory `/dashboard`**, build `npm run build`, start
`npm run start`, health check `/login` (the one page that answers 200
without a session). `railway.json` stays as the record of those values — keep
the two in step. Node comes from `.nvmrc` / `engines` (24).

### Environment variables

| Variable | Required | When | Value |
|---|---|---|---|
| `BACKEND_URL` | yes | runtime | The production backend's HTTPS URL, e.g. `https://api.<domain>` (no trailing slash). Server-only. |
| `JWT_SECRET` | yes | runtime | Exactly the production backend's `JWT_SECRET` — the new production secret, not the dev one. |
| `NEXT_PUBLIC_SENTRY_DSN` | no | **build** | Sentry DSN for the dashboard. Baked in by `next build`, so set it before building. |
| `NODE_ENV` | — | — | `next build`/`next start` set `production` themselves. |

The server refuses to start in production if `BACKEND_URL` or `JWT_SECRET` is
missing (`instrumentation.ts`), instead of failing every request.

### On the backend, for the dashboard

| Backend variable | Set to |
|---|---|
| `DASHBOARD_ORIGIN` | The dashboard's public origin, e.g. `https://dashboard.<domain>` (CORS). |
| `DASHBOARD_URL` | Same origin — password-reset emails link to `<DASHBOARD_URL>/reset-password`. |
| `JWT_SECRET` | The same value as the dashboard's. |

### Before the first real sign-in

- Create the real admin account(s) on the production database — don't run
  `prisma:seed` there (it creates the `@runit.dev` dev accounts with a published
  password).
- Sign in once as admin and once as a restaurant against production and check the
  session cookie is `Secure` (it is whenever `NODE_ENV=production`).
