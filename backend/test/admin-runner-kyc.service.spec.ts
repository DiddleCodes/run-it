import { ConflictException, NotFoundException } from '@nestjs/common';
import { AdminRunnerKycService } from '../src/admin/runner-kyc/admin-runner-kyc.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { UploadsService } from '../src/uploads/uploads.service';
import { createConfigMock, createPrismaMock } from './support/mocks';

// The real signer with dummy keys: links are computed locally, nothing is fetched.
const uploads = new UploadsService(
  createConfigMock({
    's3.region': 'eu-central-003',
    's3.endpoint': 'https://s3.eu-central-003.backblazeb2.com',
    's3.bucket': 'public-test',
    's3.privateBucket': 'private-test',
    's3.accessKeyId': 'test-key',
    's3.secretAccessKey': 'test-secret',
    's3.publicBaseUrl': 'https://s3.eu-central-003.backblazeb2.com/public-test',
  }) as any,
);
const UUID = '3f2b8c1e-9a4d-4e5f-8b6a-1c2d3e4f5a6b';
const privateRef = (purpose: string, owner: string) => `private://${purpose}/${owner}/${UUID}.jpg`;
const expectSignedLink = (value: unknown, key: string) => {
  const url = new URL(value as string);
  expect(url.origin + url.pathname).toBe(`https://s3.eu-central-003.backblazeb2.com/private-test/${key}`);
  expect(url.searchParams.get('X-Amz-Expires')).toBe('600');
  expect(url.searchParams.has('X-Amz-Signature')).toBe(true);
};


function makeService() {
  const prisma = createPrismaMock();
  const auditLog = new AdminAuditLogService(prisma as any);
  const service = new AdminRunnerKycService(prisma as any, auditLog, uploads);
  return { service, prisma };
}

describe('AdminRunnerKycService.list', () => {
  it('filters by status when given', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findMany.mockResolvedValue([]);
    prisma.runnerKyc.count.mockResolvedValue(0);

    await service.list({ status: 'pending' } as any);

    expect(prisma.runnerKyc.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { status: 'pending' } }),
    );
  });

  it('returns every status when no filter is given', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findMany.mockResolvedValue([]);
    prisma.runnerKyc.count.mockResolvedValue(0);

    await service.list({} as any);

    expect(prisma.runnerKyc.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: {} }));
  });
});

describe('AdminRunnerKycService.getOne', () => {
  it('throws when the submission does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue(null);

    await expect(service.getOne('missing')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminRunnerKycService.approve', () => {
  it('sets status to approved, clears any rejection reason, and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue({ id: 'kyc-1', userId: 'runner-1', status: 'pending' });
    prisma.runnerKyc.update.mockResolvedValue({ id: 'kyc-1', status: 'approved' });

    const result = await service.approve('admin-1', 'kyc-1');

    expect(prisma.runnerKyc.update).toHaveBeenCalledWith({
      where: { id: 'kyc-1' },
      data: { status: 'approved', rejectionReason: null, reviewedAt: expect.any(Date) },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: 'runner_kyc.approve', targetType: 'runner_kyc', targetId: 'kyc-1' }),
      }),
    );
    expect(result.status).toBe('approved');
  });

  it('throws when the submission does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue(null);

    await expect(service.approve('admin-1', 'missing')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminRunnerKycService.reject', () => {
  it('sets status to rejected with a reason, and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue({ id: 'kyc-1', userId: 'runner-1', status: 'pending' });
    prisma.runnerKyc.update.mockResolvedValue({ id: 'kyc-1', status: 'rejected', rejectionReason: 'Blurry ID photo' });

    const result = await service.reject('admin-1', 'kyc-1', 'Blurry ID photo');

    expect(prisma.runnerKyc.update).toHaveBeenCalledWith({
      where: { id: 'kyc-1' },
      data: { status: 'rejected', rejectionReason: 'Blurry ID photo', reviewedAt: expect.any(Date) },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: 'runner_kyc.reject', reason: 'Blurry ID photo' }),
      }),
    );
    expect(result.rejectionReason).toBe('Blurry ID photo');
  });

  it('refuses to reject an already-rejected submission', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue({ id: 'kyc-1', status: 'rejected' });

    await expect(service.reject('admin-1', 'kyc-1', 'again')).rejects.toThrow(ConflictException);
  });
});

describe('AdminRunnerKycService — private photos', () => {
  const kyc = {
    id: 'kyc-1',
    userId: 'runner-1',
    idPhotoUrl: privateRef('runner-kyc-id', 'runner-1'),
    selfiePhotoUrl: privateRef('runner-kyc-selfie', 'runner-1'),
    vehiclePhotoUrl: null,
  };

  it('the detail view returns 10-minute signed links on the private bucket, never the stored reference', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue({ ...kyc });

    const detail = await service.getOne('kyc-1');

    expectSignedLink(detail.idPhotoUrl, `runner-kyc-id/runner-1/${UUID}.jpg`);
    expectSignedLink(detail.selfiePhotoUrl, `runner-kyc-selfie/runner-1/${UUID}.jpg`);
    expect(detail.vehiclePhotoUrl).toBeNull();
    expect(JSON.stringify(detail)).not.toContain('private://');
  });

  it('an old plain URL in the database is not passed through', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findUnique.mockResolvedValue({ ...kyc, idPhotoUrl: 'https://old-bucket.s3.amazonaws.com/runner-kyc-id/x.jpg' });
    expect((await service.getOne('kyc-1')).idPhotoUrl).toBeNull();
  });

  it('the list carries no photos at all', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.findMany.mockResolvedValue([{ ...kyc }]);
    prisma.runnerKyc.count.mockResolvedValue(1);

    const { items } = await service.list({} as any);
    expect(items[0]).toMatchObject({ idPhotoUrl: null, selfiePhotoUrl: null, vehiclePhotoUrl: null });
  });
});
