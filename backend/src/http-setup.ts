import { NestExpressApplication } from '@nestjs/platform-express';
import { trustProxyHops } from './config/environment';

/**
 * Makes `req.ip` the real client address behind Railway's proxy — see
 * trustProxyHops. Separate from main.ts so a test can apply it to a real
 * Express app and check what `req.ip` resolves to.
 */
export function applyTrustProxy(app: NestExpressApplication, env: NodeJS.ProcessEnv = process.env): number {
  const hops = trustProxyHops(env);
  app.set('trust proxy', hops === 0 ? false : hops);
  return hops;
}
