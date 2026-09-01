import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DisputeStatus } from '@prisma/client';
import { OrderEscrowService } from '../../order-escrow/order-escrow.service';
import { PrismaService } from '../../prisma/prisma.service';
import { AdminAuditLogService } from '../admin-audit-log.service';
import { OpenDisputeDto } from './dto/open-dispute.dto';
import { DisputeResolutionInput, ResolveDisputeDto } from './dto/resolve-dispute.dto';

const ORDER_DETAIL_INCLUDE = {
  vendor: { select: { id: true, businessName: true } },
  studentUser: { select: { id: true, name: true, phone: true } },
  runnerUser: { select: { id: true, name: true, phone: true } },
  items: true,
  escrow: true,
} as const;

@Injectable()
export class AdminDisputesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly escrow: OrderEscrowService,
    private readonly auditLog: AdminAuditLogService,
  ) {}

  async list(status?: DisputeStatus) {
    return this.prisma.dispute.findMany({
      where: status ? { status } : {},
      orderBy: { openedAt: 'desc' },
      include: { order: { select: { id: true, status: true, totalAmount: true, deliveryLocationLabel: true } } },
    });
  }

  async getOne(id: string) {
    const dispute = await this.prisma.dispute.findUnique({
      where: { id },
      include: { order: { include: ORDER_DETAIL_INCLUDE } },
    });
    if (!dispute) throw new NotFoundException('Dispute not found');
    return dispute;
  }

  // Manual open — for a dispute an admin identifies outside the auto-open
  // path (submitDeliveryProof's needsManualReview signal). One dispute per
  // order (Dispute.orderId is unique), so this rejects a second dispute on
  // an order that already has one, open or resolved.
  async open(adminUserId: string, dto: OpenDisputeDto) {
    const order = await this.prisma.order.findUnique({ where: { id: dto.orderId } });
    if (!order) throw new NotFoundException('Order not found');

    const existing = await this.prisma.dispute.findUnique({ where: { orderId: dto.orderId } });
    if (existing) throw new ConflictException(`A dispute already exists for order ${dto.orderId}`);

    return this.prisma.$transaction(async (tx) => {
      const dispute = await tx.dispute.create({ data: { orderId: dto.orderId, reason: dto.reason } });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'dispute.open', targetType: 'dispute', targetId: dispute.id, reason: dto.reason },
        tx,
      );
      return dispute;
    });
  }

  // Resolution types are exactly what the existing escrow endpoints
  // support — no ad hoc payment path. `release`/`refund` call
  // OrderEscrowService directly (same validation/idempotency/Paystack
  // logic as POST /orders/:orderId/escrow/release|refund) and, if that
  // throws (e.g. refund() on already-released escrow), the error
  // propagates as-is — the dispute stays open, not silently resolved.
  async resolve(adminUserId: string, id: string, dto: ResolveDisputeDto) {
    const dispute = await this.getOne(id);
    if (dispute.status === 'resolved') {
      throw new ConflictException('Dispute is already resolved');
    }

    await this.applyResolution(dispute.order.id, dto.resolutionType);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.dispute.update({
        where: { id },
        data: {
          status: 'resolved',
          resolutionType: dto.resolutionType,
          resolutionNote: dto.note,
          resolvedBy: adminUserId,
          resolvedAt: new Date(),
        },
      });
      await this.auditLog.record(
        {
          actorId: adminUserId,
          action: `dispute.resolve.${dto.resolutionType}`,
          targetType: 'dispute',
          targetId: id,
          reason: dto.note,
        },
        tx,
      );
      return updated;
    });
  }

  private async applyResolution(orderId: string, resolutionType: DisputeResolutionInput): Promise<void> {
    if (resolutionType === 'release') {
      await this.escrow.release(orderId);
    } else if (resolutionType === 'refund') {
      await this.escrow.refund(orderId);
    }
    // 'deny': no money movement.
  }
}
