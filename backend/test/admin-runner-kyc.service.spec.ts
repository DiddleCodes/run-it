import { ConflictException, NotFoundException } from '@nestjs/common';
import { AdminRunnerKycService } from '../src/admin/runner-kyc/admin-runner-kyc.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const auditLog = new AdminAuditLogService(prisma as any);
  const service = new AdminRunnerKycService(prisma as any, auditLog);
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
