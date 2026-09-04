import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AdminAuditLogService } from '../admin-audit-log.service';
import { DEFAULT_PAGE_SIZE, ListAdminRunnerKycQueryDto, MAX_PAGE_SIZE } from './dto/list-admin-runner-kyc-query.dto';

// Task 29: mirrors AdminVendorReviewService's structure directly — same
// list/getOne/approve/reject shape, same audit-log-in-the-same-transaction
// pattern, just reviewing RunnerKyc rows instead of Vendor rows. No campus
// assignment here (unlike vendor approve) — a runner's campus is a
// separate admin action (AdminUsersService.assignCampus), unrelated to
// identity verification.
@Injectable()
export class AdminRunnerKycService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AdminAuditLogService,
  ) {}

  async list(query: ListAdminRunnerKycQueryDto) {
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    const where = query.status ? { status: query.status } : {};

    const [items, total] = await Promise.all([
      this.prisma.runnerKyc.findMany({
        where,
        orderBy: { submittedAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { user: { select: { name: true, email: true, phone: true } } },
      }),
      this.prisma.runnerKyc.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  async getOne(id: string) {
    const kyc = await this.prisma.runnerKyc.findUnique({
      where: { id },
      include: { user: { select: { name: true, email: true, phone: true, createdAt: true } } },
    });
    if (!kyc) throw new NotFoundException('Runner KYC submission not found');
    return kyc;
  }

  async approve(adminUserId: string, id: string) {
    const kyc = await this.requireKyc(id);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.runnerKyc.update({
        where: { id: kyc.id },
        data: { status: 'approved', rejectionReason: null, reviewedAt: new Date() },
      });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'runner_kyc.approve', targetType: 'runner_kyc', targetId: kyc.id },
        tx,
      );
      return updated;
    });
  }

  async reject(adminUserId: string, id: string, reason: string) {
    const kyc = await this.requireKyc(id);
    if (kyc.status === 'rejected') {
      throw new ConflictException('Runner KYC submission is already rejected');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.runnerKyc.update({
        where: { id: kyc.id },
        data: { status: 'rejected', rejectionReason: reason, reviewedAt: new Date() },
      });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'runner_kyc.reject', targetType: 'runner_kyc', targetId: kyc.id, reason },
        tx,
      );
      return updated;
    });
  }

  private async requireKyc(id: string) {
    const kyc = await this.prisma.runnerKyc.findUnique({ where: { id } });
    if (!kyc) throw new NotFoundException('Runner KYC submission not found');
    return kyc;
  }
}
