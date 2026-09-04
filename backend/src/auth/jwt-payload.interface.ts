export type AppRole = 'user' | 'admin' | 'internal_service';

export interface JwtPayload {
  sub: string; // user id
  accountType?: 'student' | 'runner' | 'restaurant' | 'admin';
  role: AppRole;
  // Task 26: null for an admin (never campus-scoped) and for a
  // restaurant/runner that hasn't been assigned one by an admin yet.
  // Embedded at sign time rather than looked up per-request, same
  // staleness tradeoff this codebase already accepts for accountType/role
  // (see AuthService.login's suspension-check doc comment) — a runner
  // reassigned to a different campus picks it up on their next login, not
  // mid-session.
  campusId?: string | null;
}
