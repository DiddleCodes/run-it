import { ConflictException, NotFoundException } from '@nestjs/common';
import { AdminDisputesService } from '../src/admin/disputes/admin-disputes.service';
import { AdminAuditLogService } from '../src/admin/admin-audit-log.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const escrow = { release: jest.fn(), refund: jest.fn() };
  const auditLog = new AdminAuditLogService(prisma as any);
  const service = new AdminDisputesService(prisma as any, escrow as any, auditLog);
  return { service, prisma, escrow };
}

const openDispute = {
  id: 'dispute-1',
  orderId: 'order-1',
  status: 'open' as const,
  order: { id: 'order-1', status: 'picked_up' },
};

describe('AdminDisputesService.open', () => {
  it('rejects opening a second dispute for an order that already has one', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1' });
    prisma.dispute.findUnique.mockResolvedValue({ id: 'dispute-existing' });

    await expect(service.open('admin-1', { orderId: 'order-1', reason: 'Customer complaint' })).rejects.toThrow(
      ConflictException,
    );
    expect(prisma.dispute.create).not.toHaveBeenCalled();
  });

  it('throws when the order does not exist', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue(null);

    await expect(service.open('admin-1', { orderId: 'missing', reason: 'x' })).rejects.toThrow(NotFoundException);
  });

  it('creates the dispute and writes an audit row', async () => {
    const { service, prisma } = makeService();
    prisma.order.findUnique.mockResolvedValue({ id: 'order-1' });
    prisma.dispute.findUnique.mockResolvedValue(null);
    prisma.dispute.create.mockResolvedValue({ id: 'dispute-1', orderId: 'order-1' });

    await service.open('admin-1', { orderId: 'order-1', reason: 'Customer complaint' });

    expect(prisma.dispute.create).toHaveBeenCalledWith({
      data: { orderId: 'order-1', reason: 'Customer complaint' },
    });
    expect(prisma.adminAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ action: 'dispute.open' }) }),
    );
  });
});

describe('AdminDisputesService.resolve', () => {
  it('resolving as release calls escrow.release and marks the dispute resolved', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.dispute.findUnique.mockResolvedValue(openDispute);
    escrow.release.mockResolvedValue({ status: 'released' });
    prisma.dispute.update.mockResolvedValue({ id: 'dispute-1', status: 'resolved', resolutionType: 'release' });

    const result = await service.resolve('admin-1', 'dispute-1', { resolutionType: 'release' });

    expect(escrow.release).toHaveBeenCalledWith('order-1');
    expect(escrow.refund).not.toHaveBeenCalled();
    expect(prisma.dispute.update).toHaveBeenCalledWith({
      where: { id: 'dispute-1' },
      data: expect.objectContaining({ status: 'resolved', resolutionType: 'release', resolvedBy: 'admin-1' }),
    });
    expect(result.status).toBe('resolved');
  });

  it('resolving as refund calls escrow.refund', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.dispute.findUnique.mockResolvedValue(openDispute);
    escrow.refund.mockResolvedValue({ status: 'refunded' });
    prisma.dispute.update.mockResolvedValue({ id: 'dispute-1', status: 'resolved', resolutionType: 'refund' });

    await service.resolve('admin-1', 'dispute-1', { resolutionType: 'refund' });

    expect(escrow.refund).toHaveBeenCalledWith('order-1');
    expect(escrow.release).not.toHaveBeenCalled();
  });

  it('resolving as deny moves no money and closes the dispute', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.dispute.findUnique.mockResolvedValue(openDispute);
    prisma.dispute.update.mockResolvedValue({ id: 'dispute-1', status: 'resolved', resolutionType: 'deny' });

    await service.resolve('admin-1', 'dispute-1', { resolutionType: 'deny' });

    expect(escrow.release).not.toHaveBeenCalled();
    expect(escrow.refund).not.toHaveBeenCalled();
    expect(prisma.dispute.update).toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ resolutionType: 'deny' }) }),
    );
  });

  it('when refund throws (e.g. escrow already released), the dispute stays open — not silently resolved', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.dispute.findUnique.mockResolvedValue(openDispute);
    escrow.refund.mockRejectedValue(new ConflictException('Escrow for order order-1 is released, not held'));

    await expect(service.resolve('admin-1', 'dispute-1', { resolutionType: 'refund' })).rejects.toThrow(
      ConflictException,
    );
    expect(prisma.dispute.update).not.toHaveBeenCalled();
    expect(prisma.adminAuditLog.create).not.toHaveBeenCalled();
  });

  it('rejects resolving an already-resolved dispute', async () => {
    const { service, prisma, escrow } = makeService();
    prisma.dispute.findUnique.mockResolvedValue({ ...openDispute, status: 'resolved' });

    await expect(service.resolve('admin-1', 'dispute-1', { resolutionType: 'deny' })).rejects.toThrow(
      ConflictException,
    );
    expect(escrow.release).not.toHaveBeenCalled();
    expect(escrow.refund).not.toHaveBeenCalled();
  });
});

describe('AdminDisputesService.list', () => {
  it('filters by status when given, and omits the filter entirely otherwise', async () => {
    const { service, prisma } = makeService();

    await service.list('open');
    expect(prisma.dispute.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: { status: 'open' } }));

    await service.list(undefined);
    expect(prisma.dispute.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: {} }));
  });
});
