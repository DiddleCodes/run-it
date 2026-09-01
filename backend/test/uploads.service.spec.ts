import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { UploadsService } from '../src/uploads/uploads.service';
import { createConfigMock } from './support/mocks';

jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn(),
}));

const S3_CONFIG = {
  's3.region': 'us-east-1',
  's3.bucket': 'run-it-uploads-test',
  's3.accessKeyId': 'AKIA_TEST',
  's3.secretAccessKey': 'secret_test',
  's3.publicBaseUrl': 'https://run-it-uploads-test.s3.us-east-1.amazonaws.com',
};

describe('UploadsService.presign', () => {
  beforeEach(() => {
    (getSignedUrl as jest.Mock).mockReset();
  });

  it('issues a presigned PUT URL under the requested purpose, with a matching public URL', async () => {
    (getSignedUrl as jest.Mock).mockResolvedValue('https://signed.example/put-url');
    const service = new UploadsService(createConfigMock(S3_CONFIG) as any);

    const result = await service.presign({
      contentType: 'image/png',
      purpose: 'menu-item-photo',
      contentLengthBytes: 200_000,
    });

    expect(result.uploadUrl).toBe('https://signed.example/put-url');
    expect(result.publicUrl).toMatch(
      /^https:\/\/run-it-uploads-test\.s3\.us-east-1\.amazonaws\.com\/menu-item-photo\/[0-9a-f-]+\.png$/,
    );
    expect(result.expiresInSeconds).toBe(300);
  });

  it('maps content-type to the correct file extension', async () => {
    (getSignedUrl as jest.Mock).mockResolvedValue('https://signed.example/put-url');
    const service = new UploadsService(createConfigMock(S3_CONFIG) as any);

    const result = await service.presign({
      contentType: 'image/jpeg',
      purpose: 'vendor-logo',
      contentLengthBytes: 50_000,
    });

    expect(result.publicUrl).toMatch(/\.jpg$/);
    expect(result.publicUrl).toContain('/vendor-logo/');
  });
});
