# RUN-It Web Dashboard

Restaurant & Admin portal for RUN-It, built with Next.js (App Router) + TypeScript +
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
cp .env.local.example .env.local   # BACKEND_URL + JWT_SECRET (must match backend/.env)
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
- `/component-library` — full showcase of the above, for design review. The only
  page in this app that uses illustrative demo data (clearly labeled as such in its
  source) — every other page either shows real data or an honest loading/empty
  state, never a fabricated number.

## What's real vs. not-yet-wired in this task

Real: login, logout, forgot/reset password, session verification, role guards
(middleware + layout), `GET /auth/me`. Not yet wired (Task 13b/13c): Orders, Menu,
Metrics, Vendor Review, Disputes, Platform Metrics, Reconciliation, and Users pages
are real, role-guarded routes rendering an honest "coming in a later task" empty
state — not mocked tables standing in for a real API call.
