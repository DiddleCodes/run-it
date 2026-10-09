import { UploadsService } from '../src/uploads/uploads.service';
import { createConfigMock } from './support/mocks';

// Real presigning with dummy keys — nothing leaves the process — so these
// check the actual URLs storage will be asked to accept.
const AWS = {
  's3.region': 'eu-west-1',
  's3.bucket': 'bridgit-public-test',
  's3.privateBucket': 'bridgit-private-test',
  's3.accessKeyId': 'AKIATESTTESTTEST',
  's3.secretAccessKey': 'test-secret',
  's3.publicBaseUrl': 'https://bridgit-public-test.s3.eu-west-1.amazonaws.com',
};
const B2 = {
  ...AWS,
  's3.region': 'eu-central-003',
  's3.endpoint': 'https://s3.eu-central-003.backblazeb2.com',
  's3.publicBaseUrl': 'https://s3.eu-central-003.backblazeb2.com/bridgit-public-test',
};
const R2 = {
  ...AWS,
  's3.region': 'auto',
  's3.endpoint': 'https://accountid.r2.cloudflarestorage.com',
  's3.publicBaseUrl': 'https://media.bridgitcampus.com',
};

const service = (config: Record<string, unknown>) => new UploadsService(createConfigMock(config) as any);
const presign = (config: Record<string, unknown>, purpose: string, bytes = 200_000) =>
  service(config).presign({ contentType: 'image/png', purpose: purpose as any, contentLengthBytes: bytes }, 'runner-1');

describe('UploadsService.presign', () => {
  it('a public photo goes to the public bucket and gets a public URL', async () => {
    const result = await presign(AWS, 'menu-item-photo');
    const url = new URL(result.uploadUrl);

    expect(url.host).toBe('bridgit-public-test.s3.eu-west-1.amazonaws.com');
    expect(result.publicUrl).toMatch(
      /^https:\/\/bridgit-public-test\.s3\.eu-west-1\.amazonaws\.com\/menu-item-photo\/[0-9a-f-]{36}\.png$/,
    );
    expect(result.fileUrl).toBe(result.publicUrl);
    expect(result.expiresInSeconds).toBe(300);
  });

  it.each(['runner-kyc-id', 'runner-kyc-selfie', 'runner-kyc-vehicle', 'delivery-proof', 'handoff-photo', 'dispute-report'])(
    'a %s photo goes to the private bucket and never gets a public URL',
    async (purpose) => {
      const result = await presign(AWS, purpose);
      const url = new URL(result.uploadUrl);

      expect(url.host).toBe('bridgit-private-test.s3.eu-west-1.amazonaws.com');
      expect(url.pathname).toMatch(new RegExp(`^/${purpose}/runner-1/[0-9a-f-]{36}\\.png$`));
      expect(result.publicUrl).toBeNull();
      expect(result.fileUrl).toMatch(new RegExp(`^private://${purpose}/runner-1/[0-9a-f-]{36}\\.png$`));
    },
  );

  it('signs the exact size and type into the URL, so storage refuses anything else (the 5 MB cap holds)', async () => {
    const url = new URL((await presign(AWS, 'vendor-logo', 4_321)).uploadUrl);
    expect(url.searchParams.get('X-Amz-SignedHeaders')?.split(';')).toEqual(
      expect.arrayContaining(['content-length', 'content-type', 'host']),
    );
  });

  it('carries no checksum parameters (the SDK default made every real upload fail)', async () => {
    for (const config of [AWS, B2, R2]) {
      const url = new URL((await presign(config, 'menu-item-photo')).uploadUrl);
      expect([...url.searchParams.keys()].filter((k) => /checksum/i.test(k))).toEqual([]);
    }
  });

  it('with S3_ENDPOINT, talks to that store path-style — Backblaze B2', async () => {
    const pub = await presign(B2, 'menu-item-photo');
    expect(new URL(pub.uploadUrl).host).toBe('s3.eu-central-003.backblazeb2.com');
    expect(new URL(pub.uploadUrl).pathname).toMatch(/^\/bridgit-public-test\/menu-item-photo\//);
    expect(pub.publicUrl).toMatch(/^https:\/\/s3\.eu-central-003\.backblazeb2\.com\/bridgit-public-test\/menu-item-photo\//);

    const priv = await presign(B2, 'runner-kyc-id');
    expect(new URL(priv.uploadUrl).pathname).toMatch(/^\/bridgit-private-test\/runner-kyc-id\/runner-1\//);
    expect(new URL(priv.uploadUrl).searchParams.get('X-Amz-Credential')).toContain('/eu-central-003/s3/');
  });

  it('with S3_ENDPOINT, talks to that store path-style — Cloudflare R2', async () => {
    const result = await presign(R2, 'vendor-logo');
    expect(new URL(result.uploadUrl).host).toBe('accountid.r2.cloudflarestorage.com');
    expect(new URL(result.uploadUrl).pathname).toMatch(/^\/bridgit-public-test\/vendor-logo\//);
    expect(result.publicUrl).toMatch(/^https:\/\/media\.bridgitcampus\.com\/vendor-logo\//);
  });
});

describe('UploadsService.signedReadUrl', () => {
  it('signs a 10-minute GET on the private bucket for a private reference', async () => {
    const ref = (await presign(B2, 'runner-kyc-selfie')).fileUrl;
    const url = new URL((await service(B2).signedReadUrl(ref)) as string);

    expect(url.host).toBe('s3.eu-central-003.backblazeb2.com');
    expect(url.pathname).toBe(`/bridgit-private-test/${ref.slice('private://'.length)}`);
    expect(url.searchParams.get('X-Amz-Expires')).toBe('600');
    expect(url.searchParams.get('X-Amz-Signature')).toMatch(/^[0-9a-f]{64}$/);
  });

  it('never passes anything else through — empty values and old plain URLs give null', async () => {
    const s = service(AWS);
    expect(await s.signedReadUrl(null)).toBeNull();
    expect(await s.signedReadUrl('')).toBeNull();
    expect(await s.signedReadUrl('https://run-it-uploads.s3.amazonaws.com/runner-kyc-id/x.jpg')).toBeNull();
    expect(await s.signedReadUrl('private://menu-item-photo/runner-1/00000000-0000-4000-8000-000000000000.png')).toBeNull();
    expect(await s.signedReadUrl('private://runner-kyc-id/../../etc/passwd')).toBeNull();
  });
});
