import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

/**
 * Task 17: extracted from `/auth/dev-token`'s own inline check into a
 * reusable, testable guard — same inverse-of-`PaystackWebhookIpGuard`
 * shape (disabled *in* production instead of enabled only *in*
 * production) that route's own doc comment already described, just not
 * previously factored out or covered by any test.
 */
@Injectable()
export class DevOnlyGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(): boolean {
    if (this.config.get<string>('nodeEnv') === 'production') {
      throw new ForbiddenException('This endpoint is disabled in production');
    }
    return true;
  }
}
