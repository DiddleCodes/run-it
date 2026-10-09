import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { AuthService } from '../src/auth/auth.service';
import { DevOnlyGuard } from '../src/common/guards/dev-only.guard';
import configuration from '../src/config/configuration';
import { isDevEnvironment } from '../src/config/environment';
import { envValidationSchema } from '../src/config/env.validation';
import { PaystackWebhookIpGuard } from '../src/webhooks/paystack-webhook-ip.guard';
import { createConfigMock, createPrismaMock } from './support/mocks';

/** Everything env.validation requires, so only NODE_ENV varies. */
const REQUIRED_ENV = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  REDIS_URL: 'redis://localhost:6379',
  PAYSTACK_SECRET_KEY: 'sk_test_x',
  PAYSTACK_PUBLIC_KEY: 'pk_test_x',
  JWT_SECRET: 'a-long-enough-test-secret',
  INTERNAL_SERVICE_API_KEY: 'internal-key',
  S3_UPLOADS_BUCKET: 'bucket',
  S3_PRIVATE_BUCKET: 'private-bucket',
  AWS_ACCESS_KEY_ID: 'id',
  AWS_SECRET_ACCESS_KEY: 'secret',
};

function authService(nodeEnv: string | undefined) {
  const prisma = createPrismaMock();
  prisma.otpVerification.deleteMany.mockResolvedValue({ count: 0 });
  prisma.otpVerification.create.mockResolvedValue({});
  prisma.user.findUnique.mockResolvedValue({ id: 'u1', accountType: 'restaurant' });
  prisma.passwordResetToken.create.mockResolvedValue({});
  const email = { send: jest.fn().mockResolvedValue(false) }; // Brevo not configured / failed
  const campus = { resolveByEmail: jest.fn().mockResolvedValue({ id: 'c1' }) };
  const service = new AuthService(
    prisma as any,
    { sign: jest.fn() } as any,
    email as any,
    createConfigMock({ nodeEnv, dashboardUrl: 'https://dashboard.example' }) as any,
    campus as any,
  );
  const warn = jest.spyOn((service as any).logger, 'warn');
  return { service, warn };
}

describe('NODE_ENV safe default — dev conveniences need an explicit development/test', () => {
  it('isDevEnvironment', () => {
    expect(isDevEnvironment('development')).toBe(true);
    expect(isDevEnvironment('test')).toBe(true);
    for (const value of [undefined, '', 'production', 'staging', 'Development', 'dev']) {
      expect(isDevEnvironment(value)).toBe(false);
    }
  });

  describe('the real config pipeline leaves an unset NODE_ENV unset', () => {
    const original = process.env.NODE_ENV;
    afterEach(() => {
      process.env.NODE_ENV = original;
    });

    it('the validation schema adds no default', () => {
      const { error, value } = envValidationSchema.validate(REQUIRED_ENV);
      expect(error).toBeUndefined();
      expect(value.NODE_ENV).toBeUndefined();
    });

    it('ConfigModule does not write "development" back into process.env', async () => {
      delete process.env.NODE_ENV;
      for (const [k, v] of Object.entries(REQUIRED_ENV)) process.env[k] ??= v;
      const moduleRef = await Test.createTestingModule({
        imports: [
          ConfigModule.forRoot({ ignoreEnvFile: true, load: [configuration], validationSchema: envValidationSchema }),
        ],
      }).compile();

      expect(process.env.NODE_ENV).toBeUndefined();
      expect(isDevEnvironment(moduleRef.get(ConfigService).get('nodeEnv'))).toBe(false);
    });
  });

  describe.each([
    ['unset', undefined],
    ['a typo ("staging")', 'staging'],
  ])('with NODE_ENV %s', (_label, nodeEnv) => {
    it('the dev-token endpoint is closed', () => {
      const guard = new DevOnlyGuard(createConfigMock({ nodeEnv }) as any);
      expect(() => guard.canActivate()).toThrow(ForbiddenException);
    });

    it('a failed sign-in code email does not log the code', async () => {
      const { service, warn } = authService(nodeEnv);
      await service.requestOtp('runner@example.com', 'runner');
      expect(warn).not.toHaveBeenCalled();
    });

    it('a failed password-reset email does not log the link', async () => {
      const { service, warn } = authService(nodeEnv);
      await service.requestPasswordReset('r@example.com');
      expect(warn).not.toHaveBeenCalled();
    });

    it('the Paystack webhook IP allowlist is enforced', () => {
      const guard = new PaystackWebhookIpGuard(
        createConfigMock({ nodeEnv, 'paystack.webhookIpAllowlist': ['52.31.139.75'] }) as any,
      );
      const context = {
        switchToHttp: () => ({ getRequest: () => ({ ip: '1.2.3.4', headers: {} }) }),
      } as unknown as ExecutionContext;
      expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
    });
  });

  it('with NODE_ENV=development, the dev conveniences still work locally', async () => {
    expect(new DevOnlyGuard(createConfigMock({ nodeEnv: 'development' }) as any).canActivate()).toBe(true);
    const { service, warn } = authService('development');
    await service.requestOtp('runner@example.com', 'runner');
    expect(warn.mock.calls[0][0]).toContain('[DEV ONLY]');
  });
});
