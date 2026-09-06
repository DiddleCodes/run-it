import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { AdminCampusService } from '../src/admin/campus/admin-campus.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { CampusService } from '../src/campus/campus.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const auditLog = new AdminAuditLogService(prisma as any);
  const campus = new CampusService(prisma as any);
  const service = new AdminCampusService(prisma as any, campus, auditLog);
  return { service, prisma, campus };
}

describe('AdminCampusService.list', () => {
  it('returns every campus (active or not) with real student/vendor counts', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findMany.mockResolvedValue([
      { id: 'campus-1', name: 'Uni A', allowedEmailDomains: ['a.edu'], isActive: true, createdAt: new Date() },
    ]);
    prisma.user.count.mockResolvedValue(5);
    prisma.vendor.count.mockResolvedValue(2);

    const result = await service.list();

    expect(prisma.user.count).toHaveBeenCalledWith({
      where: { campusId: 'campus-1', accountType: 'student', suspendedAt: null },
    });
    expect(prisma.vendor.count).toHaveBeenCalledWith({ where: { user: { campusId: 'campus-1' }, status: 'active' } });
    expect(result).toEqual([expect.objectContaining({ id: 'campus-1', studentCount: 5, vendorCount: 2 })]);
  });
});

describe('AdminCampusService.create', () => {
  it('normalizes domains (trim, lowercase, dedupe) and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.campus.create.mockResolvedValue({ id: 'campus-1', name: 'Uni A' });

    await service.create('admin-1', {
      name: 'Uni A',
      allowedEmailDomains: [' Student.A.edu ', 'student.a.edu', 'STUDENT.A.EDU'],
    });

    expect(prisma.campus.create).toHaveBeenCalledWith({
      data: { name: 'Uni A', allowedEmailDomains: ['student.a.edu'] },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'campus.create' }) }),
    );
  });

  it('rejects a domain list that normalizes to nothing', async () => {
    const { service, prisma } = makeService();

    await expect(service.create('admin-1', { name: 'Uni A', allowedEmailDomains: ['  ', ''] })).rejects.toThrow(
      BadRequestException,
    );
    expect(prisma.campus.create).not.toHaveBeenCalled();
  });
});

describe('AdminCampusService.update', () => {
  it('throws when the campus does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue(null);

    await expect(service.update('admin-1', 'missing', { name: 'New name' })).rejects.toThrow(NotFoundException);
  });

  it('updates only the fields provided, normalizing domains', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1', name: 'Old', allowedEmailDomains: ['old.edu'] });
    prisma.campus.update.mockResolvedValue({ id: 'campus-1', name: 'New' });

    await service.update('admin-1', 'campus-1', { name: 'New' });

    expect(prisma.campus.update).toHaveBeenCalledWith({ where: { id: 'campus-1' }, data: { name: 'New' } });
  });
});

describe('AdminCampusService.deactivate / reactivate', () => {
  it('deactivates an active campus and audit-logs it', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1', isActive: true });
    prisma.campus.update.mockResolvedValue({ id: 'campus-1', isActive: false });

    await service.deactivate('admin-1', 'campus-1');

    expect(prisma.campus.update).toHaveBeenCalledWith({ where: { id: 'campus-1' }, data: { isActive: false } });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'campus.deactivate' }) }),
    );
  });

  it('rejects deactivating an already-inactive campus', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1', isActive: false });

    await expect(service.deactivate('admin-1', 'campus-1')).rejects.toThrow(ConflictException);
    expect(prisma.campus.update).not.toHaveBeenCalled();
  });

  it('rejects reactivating an already-active campus', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1', isActive: true });

    await expect(service.reactivate('admin-1', 'campus-1')).rejects.toThrow(ConflictException);
    expect(prisma.campus.update).not.toHaveBeenCalled();
  });
});

// Task 51: the schema's own FKs (User.campusId, Vendor.requestedCampusId)
// are ON DELETE SET NULL, so Postgres itself would happily orphan real
// data rather than block a delete — this application-level check is the
// only real guard.
describe('AdminCampusService.remove', () => {
  it('rejects deleting a campus with real users or vendor applications attached', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1' });
    prisma.user.count.mockResolvedValue(3);
    prisma.vendor.count.mockResolvedValue(0);

    await expect(service.remove('admin-1', 'campus-1')).rejects.toThrow(ConflictException);
    expect(prisma.campus.delete).not.toHaveBeenCalled();
  });

  it('hard-deletes a genuinely unused campus and audit-logs it', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue({ id: 'campus-1' });
    prisma.user.count.mockResolvedValue(0);
    prisma.vendor.count.mockResolvedValue(0);

    const result = await service.remove('admin-1', 'campus-1');

    expect(prisma.campus.delete).toHaveBeenCalledWith({ where: { id: 'campus-1' } });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'campus.delete', targetId: 'campus-1' }) }),
    );
    expect(result).toEqual({ id: 'campus-1', deleted: true });
  });

  it('throws when the campus does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.campus.findUnique.mockResolvedValue(null);

    await expect(service.remove('admin-1', 'missing')).rejects.toThrow(NotFoundException);
  });
});
