import { BadRequestException, NotFoundException } from '@nestjs/common';
import { AdminUsersService } from '../src/admin/users/admin-users.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { createNotificationsEmitterMock, createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const auditLog = new AdminAuditLogService(prisma as any);
  const notifications = createNotificationsEmitterMock();
  const campus = {
    resolveByEmail: jest.fn(),
    requireById: jest.fn().mockResolvedValue({ id: 'campus-1', name: 'Test Campus', allowedEmailDomains: [] }),
    list: jest.fn(),
  };
  const service = new AdminUsersService(prisma as any, auditLog, notifications as any, campus as any);
  return { service, prisma, notifications, campus };
}

describe('AdminUsersService.list', () => {
  it('filters by accountType and searches name/email/phone case-insensitively', async () => {
    const { service, prisma } = makeService();

    await service.list({ accountType: 'restaurant', search: 'ada' });

    expect(prisma.user.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          accountType: 'restaurant',
          OR: [
            { name: { contains: 'ada', mode: 'insensitive' } },
            { email: { contains: 'ada', mode: 'insensitive' } },
            { phone: { contains: 'ada', mode: 'insensitive' } },
          ],
        },
      }),
    );
  });

  it('never selects the password field', async () => {
    const { service, prisma } = makeService();

    await service.list({});

    const call = prisma.user.findMany.mock.calls[0][0];
    expect(call.select.password).toBeUndefined();
  });
});

describe('AdminUsersService.suspend', () => {
  it('sets suspendedAt, cascades a restaurant vendor to inactive, and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'user-1', accountType: 'restaurant' });
    prisma.user.update.mockResolvedValue({ id: 'user-1', suspendedAt: new Date() });

    await service.suspend('admin-1', 'user-1', 'Repeated food safety complaints');

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'user-1' }, data: expect.objectContaining({ suspendedAt: expect.any(Date) }) }),
    );
    expect(prisma.vendor.updateMany).toHaveBeenCalledWith({ where: { userId: 'user-1' }, data: { status: 'inactive' } });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ action: 'user.suspend', reason: 'Repeated food safety complaints' }),
      }),
    );
  });

  it('does not touch the vendor table for a student/runner (no cascade target)', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'user-2', accountType: 'student' });
    prisma.user.update.mockResolvedValue({ id: 'user-2', suspendedAt: new Date() });

    await service.suspend('admin-1', 'user-2', 'Fraudulent order dispute pattern');

    expect(prisma.vendor.updateMany).not.toHaveBeenCalled();
  });

  it('throws when the user does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.suspend('admin-1', 'missing', 'reason')).rejects.toThrow(NotFoundException);
  });

  // Task 34: suspending must close off the mobile refresh-token path too —
  // otherwise a suspended student/runner could keep minting brand new
  // access tokens forever via /auth/refresh even though their old one
  // already stopped working.
  it('revokes every live refresh token this user holds', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'user-1', accountType: 'student' });
    prisma.user.update.mockResolvedValue({ id: 'user-1', suspendedAt: new Date() });

    await service.suspend('admin-1', 'user-1', 'Fraudulent order dispute pattern');

    expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', revokedAt: null },
      data: { revokedAt: expect.any(Date) },
    });
  });
});

describe('AdminUsersService.reinstate', () => {
  it('clears suspendedAt and writes an audit row, without touching the vendor table', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'user-1', accountType: 'restaurant' });
    prisma.user.update.mockResolvedValue({ id: 'user-1', suspendedAt: null });

    await service.reinstate('admin-1', 'user-1');

    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'user-1' }, data: { suspendedAt: null } }),
    );
    expect(prisma.vendor.updateMany).not.toHaveBeenCalled();
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'user.reinstate' }) }),
    );
  });
});

// Task 26: the admin-assignment mechanism for a restaurant/runner's campus.
describe('AdminUsersService.assignCampus', () => {
  it('sets campusId after validating the campus exists, and writes an audit row', async () => {
    const { service, prisma, campus } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', accountType: 'runner' });
    prisma.user.update.mockResolvedValue({ id: 'runner-1', campusId: 'campus-1' });

    await service.assignCampus('admin-1', 'runner-1', 'campus-1');

    expect(campus.requireById).toHaveBeenCalledWith('campus-1');
    expect(prisma.user.update).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'runner-1' }, data: { campusId: 'campus-1' } }),
    );
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'user.assign_campus' }) }),
    );
  });

  it('rejects assigning a campus to an admin account', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'admin-2', accountType: 'admin' });

    await expect(service.assignCampus('admin-1', 'admin-2', 'campus-1')).rejects.toThrow(BadRequestException);
    expect(prisma.user.update).not.toHaveBeenCalled();
  });

  it('throws when the user does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.assignCampus('admin-1', 'missing', 'campus-1')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminUsersService.getOne — Task 47 cash-collection debt visibility', () => {
  it('surfaces a runner\'s real outstanding Pay on Delivery cash debt', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', accountType: 'runner', vendor: null, wallet: { balance: 5_000 } });
    prisma.cashCollectionDebt.aggregate.mockResolvedValue({ _sum: { amountOwed: 12_000 } });

    const result = await service.getOne('runner-1');

    expect(prisma.cashCollectionDebt.aggregate).toHaveBeenCalledWith({
      where: { runnerId: 'runner-1', status: { in: ['pending', 'disputed'] } },
      _sum: { amountOwed: true },
    });
    expect(result.outstandingCashDebtKobo).toBe(12_000);
  });

  it('is null for a non-runner account, without ever querying cash debts', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'student-1', accountType: 'student', vendor: null, wallet: { balance: 5_000 } });

    const result = await service.getOne('student-1');

    expect(prisma.cashCollectionDebt.aggregate).not.toHaveBeenCalled();
    expect(result.outstandingCashDebtKobo).toBeNull();
  });

  it('throws when the user does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue(null);

    await expect(service.getOne('missing')).rejects.toThrow(NotFoundException);
  });
});

describe('AdminUsersService.settleCashDebt', () => {
  it('settles every outstanding debt for a runner in one action and audit-logs it', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'runner-1', accountType: 'runner' });
    prisma.cashCollectionDebt.updateMany.mockResolvedValue({ count: 3 });
    prisma.cashCollectionDebt.aggregate.mockResolvedValue({ _sum: { amountOwed: 0 } });

    const result = await service.settleCashDebt('admin-1', 'runner-1');

    expect(prisma.cashCollectionDebt.updateMany).toHaveBeenCalledWith({
      where: { runnerId: 'runner-1', status: { in: ['pending', 'disputed'] } },
      data: { status: 'settled', settledAt: expect.any(Date), settledBy: 'admin-1' },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'user.settle_cash_debt' }) }),
    );
    expect(result).toEqual({ runnerId: 'runner-1', settledCount: 3, outstandingCashDebtKobo: 0 });
  });

  it('rejects settling a cash debt for a non-runner account', async () => {
    const { service, prisma } = makeService();
    prisma.user.findUnique.mockResolvedValue({ id: 'student-1', accountType: 'student' });

    await expect(service.settleCashDebt('admin-1', 'student-1')).rejects.toThrow(BadRequestException);
    expect(prisma.cashCollectionDebt.updateMany).not.toHaveBeenCalled();
  });
});
