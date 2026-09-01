import { ForbiddenException } from '@nestjs/common';
import { DevOnlyGuard } from '../src/common/guards/dev-only.guard';
import { createConfigMock } from './support/mocks';

describe('DevOnlyGuard', () => {
  it('allows the request through outside production', () => {
    const guard = new DevOnlyGuard(createConfigMock({ nodeEnv: 'development' }) as any);
    expect(guard.canActivate()).toBe(true);
  });

  it('allows the request through in the test environment', () => {
    const guard = new DevOnlyGuard(createConfigMock({ nodeEnv: 'test' }) as any);
    expect(guard.canActivate()).toBe(true);
  });

  // Task 17: this is the actual runtime enforcement behind /auth/dev-token
  // self-disabling in production — previously an inline check in the
  // controller with no test coverage at all.
  it('rejects the request in production', () => {
    const guard = new DevOnlyGuard(createConfigMock({ nodeEnv: 'production' }) as any);
    expect(() => guard.canActivate()).toThrow(ForbiddenException);
  });
});
