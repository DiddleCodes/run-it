/**
 * Dev conveniences — logging sign-in codes and reset links, the dev-token
 * endpoint, skipping the Paystack webhook IP allowlist — are on only when
 * NODE_ENV is explicitly "development" or "test". Unset, misspelled or
 * anything else behaves as production, so a host that forgets to set
 * NODE_ENV fails safe instead of leaking codes and tokens.
 */
export function isDevEnvironment(nodeEnv: string | undefined): boolean {
  return nodeEnv === 'development' || nodeEnv === 'test';
}

/**
 * How many reverse proxies sit in front of the app, for Express's
 * `trust proxy`. With the right count, `req.ip` is the real client's
 * address taken from X-Forwarded-For — which the Paystack webhook IP
 * allowlist and every rate limit key on. Too low and every request looks
 * like it came from the proxy; too high and a client can spoof its IP by
 * sending its own X-Forwarded-For.
 *
 * TRUST_PROXY_HOPS wins when set (0 turns it off). Otherwise: 1 outside
 * development/test (Railway's edge proxy), 0 locally.
 */
export function trustProxyHops(env: { NODE_ENV?: string; TRUST_PROXY_HOPS?: string }): number {
  const explicit = env.TRUST_PROXY_HOPS?.trim();
  if (explicit) {
    const hops = Number(explicit);
    if (!Number.isInteger(hops) || hops < 0) {
      throw new Error(`TRUST_PROXY_HOPS must be a whole number, 0 or more (got "${env.TRUST_PROXY_HOPS}")`);
    }
    return hops;
  }
  return isDevEnvironment(env.NODE_ENV) ? 0 : 1;
}
