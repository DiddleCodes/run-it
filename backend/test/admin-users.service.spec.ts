import { NotFoundException } from '@nestjs/common';
import { AdminUsersService } from '../src/admin/users/admin-users.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { createNotificationsEmitterMock, createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const auditLog = new AdminAuditLogService(prisma as any);
  const notifications = createNotificationsEmitterMock();
  const service = new AdminUsersService(prisma as any, auditLog, notifications as any);
  return { service, prisma, notifications };
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
