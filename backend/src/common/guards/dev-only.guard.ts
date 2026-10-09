import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { isDevEnvironment } from '../../config/environment';

/**
 * Task 17: extracted from `/auth/dev-token`'s own inline check into a
 * reusable, testable guard — same inverse-of-`PaystackWebhookIpGuard`
 * shape (disabled *in* production instead of enabled only *in*
 * production) that route's own doc comment already described, just not
 * previously factored out or covered by any test.
 *
 * Open only when NODE_ENV is explicitly development or test; unset or
 * anything else is treated as production (isDevEnvironment).
 */
@Injectable()
export class DevOnlyGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(): boolean {
    if (!isDevEnvironment(this.config.get<string>('nodeEnv'))) {
      throw new ForbiddenException('This endpoint is only available in development');
    }
    return true;
  }
}
