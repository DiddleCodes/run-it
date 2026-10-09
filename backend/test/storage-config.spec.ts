import configuration from '../src/config/configuration';
import { envValidationSchema } from '../src/config/env.validation';

const BASE = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  REDIS_URL: 'redis://localhost:6379',
  PAYSTACK_SECRET_KEY: 'sk_test_x',
  PAYSTACK_PUBLIC_KEY: 'pk_test_x',
  JWT_SECRET: 'a-long-enough-test-secret',
  INTERNAL_SERVICE_API_KEY: 'internal-key',
  S3_UPLOADS_BUCKET: 'bridgit-public',
  S3_PRIVATE_BUCKET: 'bridgit-private',
  AWS_ACCESS_KEY_ID: 'id',
  AWS_SECRET_ACCESS_KEY: 'secret',
};
const errorOf = (env: Record<string, string>) => envValidationSchema.validate(env, { abortEarly: false }).error?.message;

describe('storage settings', () => {
  it('AWS needs no endpoint and no public base URL', () => {
    expect(errorOf(BASE)).toBeUndefined();
    expect(errorOf({ ...BASE, S3_ENDPOINT: '' })).toBeUndefined();
  });

  it('a private bucket is required, and must not be the public one', () => {
    const { S3_PRIVATE_BUCKET: _omit, ...withoutPrivate } = BASE;
    expect(errorOf(withoutPrivate)).toMatch(/S3_PRIVATE_BUCKET" is required/);
    expect(errorOf({ ...BASE, S3_PRIVATE_BUCKET: 'bridgit-public' })).toMatch(/must be a different bucket/);
  });

  it('with S3_ENDPOINT (B2, R2), S3_PUBLIC_BASE_URL is required', () => {
    const b2 = { ...BASE, S3_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com' };
    expect(errorOf(b2)).toMatch(/S3_PUBLIC_BASE_URL" is required/);
    expect(errorOf({ ...b2, S3_PUBLIC_BASE_URL: 'https://s3.eu-central-003.backblazeb2.com/bridgit-public' })).toBeUndefined();
  });

  describe('configuration', () => {
    const saved = { ...process.env };
    afterEach(() => {
      process.env = { ...saved };
    });

    it('AWS default public URL, no endpoint', () => {
      Object.assign(process.env, BASE, { AWS_REGION: 'eu-west-1' });
      delete process.env.S3_ENDPOINT;
      delete process.env.S3_PUBLIC_BASE_URL;
      expect(configuration().s3).toMatchObject({
        endpoint: undefined,
        bucket: 'bridgit-public',
        privateBucket: 'bridgit-private',
        publicBaseUrl: 'https://bridgit-public.s3.eu-west-1.amazonaws.com',
      });
    });

    it('B2: endpoint and public base URL as given, trailing slash dropped', () => {
      Object.assign(process.env, BASE, {
        AWS_REGION: 'eu-central-003',
        S3_ENDPOINT: 'https://s3.eu-central-003.backblazeb2.com',
        S3_PUBLIC_BASE_URL: 'https://s3.eu-central-003.backblazeb2.com/bridgit-public/',
      });
      expect(configuration().s3).toMatchObject({
        endpoint: 'https://s3.eu-central-003.backblazeb2.com',
        publicBaseUrl: 'https://s3.eu-central-003.backblazeb2.com/bridgit-public',
      });
    });
  });
});
