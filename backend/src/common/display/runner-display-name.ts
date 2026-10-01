// Task 73: "Chidi Okafor" -> "Chidi O.", "Chidi" -> "Chidi"; a runner with
// no stored name (possible for older OTP signups) is still honestly "Your
// runner" rather than an invented one.
//
// Its own file (not orders.service) so any service can use it without
// importing OrdersService — OrdersService itself imports OrderEscrowService,
// and a cycle between the two leaves Nest with an undefined dependency.
export function runnerDisplayName(name: string | null | undefined): string {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'Your runner';
  if (parts.length === 1) return parts[0];
  return `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.`;
}
