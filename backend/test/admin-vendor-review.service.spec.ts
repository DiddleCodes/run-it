import { ConflictException, NotFoundException } from '@nestjs/common';
import { AdminVendorReviewService } from '../src/admin/vendor-review/admin-vendor-review.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const payoutAccounts = { findByUserId: jest.fn() };
  const auditLog = new AdminAuditLogService(prisma as any);
  const service = new AdminVendorReviewService(prisma as any, payoutAccounts as any, auditLog);
  return { service, prisma, payoutAccounts };
}

describe('AdminVendorReviewService.getOne', () => {
  it('includes the payout account when one exists', async () => {
    const { service, prisma, payoutAccounts } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', userId: 'user-1', user: {} });
    payoutAccounts.findByUserId.mockResolvedValue({ accountName: 'Suya Spot Ltd' });

    const result = await service.getOne('vendor-1');

    expect(payoutAccounts.findByUserId).toHaveBeenCalledWith('user-1');
    expect(result.payoutAccount).toEqual({ accountName: 'Suya Spot Ltd' });
  });

  it('returns null (not an error) when no payout account is on file yet', async () => {
    const { service, prisma, payoutAccounts } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', userId: 'user-1', user: {} });
    payoutAccounts.findByUserId.mockRejectedValue(new NotFoundException('No payout account on file'));

    const result = await service.getOne('vendor-1');

    expect(result.payoutAccount).toBeNull();
  });

  it('throws when the vendor does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue(null);

    await expect(service.getOne('missing')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminVendorReviewService.approve', () => {
  it('sets status to active, clears any rejectionReason, and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', status: 'pending' });
    prisma.vendor.update.mockResolvedValue({ id: 'vendor-1', status: 'active' });

    const result = await service.approve('admin-1', 'vendor-1');

    expect(prisma.vendor.update).toHaveBeenCalledWith({
      where: { id: 'vendor-1' },
      data: { status: 'active', rejectionReason: null },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ actorId: 'admin-1', action: 'vendor.approve', targetId: 'vendor-1' }),
      }),
    );
    expect(result.status).toBe('active');
  });

  it('throws when the vendor does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue(null);

    await expect(service.approve('admin-1', 'missing')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminVendorReviewService.reject', () => {
  it('sets status to rejected, stores the reason, and writes an audit row with the reason', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', status: 'pending' });
    prisma.vendor.update.mockResolvedValue({ id: 'vendor-1', status: 'rejected' });

    await service.reject('admin-1', 'vendor-1', 'Missing business registration');

    expect(prisma.vendor.update).toHaveBeenCalledWith({
      where: { id: 'vendor-1' },
      data: { status: 'rejected', rejectionReason: 'Missing business registration' },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ reason: 'Missing business registration', action: 'vendor.reject' }),
      }),
    );
  });

  it('rejects rejecting an already-rejected vendor', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findUnique.mockResolvedValue({ id: 'vendor-1', status: 'rejected' });

    await expect(service.reject('admin-1', 'vendor-1', 'reason')).rejects.toThrow(ConflictException);
    expect(prisma.vendor.update).not.toHaveBeenCalled();
  });
});

describe('AdminVendorReviewService.list', () => {
  it('filters by status when given, and omits the filter entirely otherwise', async () => {
    const { service, prisma } = makeService();
    prisma.vendor.findMany.mockResolvedValue([]);
    prisma.vendor.count.mockResolvedValue(0);

    await service.list({ status: 'pending' });
    expect(prisma.vendor.findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { status: 'pending' } }),
    );

    await service.list({});
    expect(prisma.vendor.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: {} }));
  });
});
