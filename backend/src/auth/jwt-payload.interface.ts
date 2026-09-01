export type AppRole = 'user' | 'admin' | 'internal_service';

export interface JwtPayload {
  sub: string; // user id
  accountType?: 'student' | 'runner' | 'restaurant' | 'admin';
  role: AppRole;
}
