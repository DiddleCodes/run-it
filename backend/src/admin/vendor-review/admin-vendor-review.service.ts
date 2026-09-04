import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { CampusService } from '../../campus/campus.service';
import { PrismaService } from '../../prisma/prisma.service';
import { PayoutAccountsService } from '../../payout-accounts/payout-accounts.service';
import { AdminAuditLogService } from '../admin-audit-log.service';
import {
  DEFAULT_PAGE_SIZE,
  ListAdminVendorsQueryDto,
  MAX_PAGE_SIZE,
} from './dto/list-admin-vendors-query.dto';

@Injectable()
export class AdminVendorReviewService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly payoutAccounts: PayoutAccountsService,
    private readonly auditLog: AdminAuditLogService,
    private readonly campus: CampusService,
  ) {}

  async list(query: ListAdminVendorsQueryDto) {
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    const where = query.status ? { status: query.status } : {};

    const [items, total] = await Promise.all([
      this.prisma.vendor.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: {
          user: { select: { name: true, email: true, phone: true } },
          requestedCampus: { select: { id: true, name: true } },
        },
      }),
      this.prisma.vendor.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  // Full review detail: business info (contactName/contactPhone still live
  // only in the Flutter client's local draft and are never sent to
  // POST /vendors/me, so this doesn't fabricate those two — but
  // requestedCampus is real, Task 27 wired it through) + owner contact +
  // payout account, resolved via vendor.userId (the same userId a
  // PayoutAccount is keyed on) rather than a second HTTP hop.
  async getOne(id: string) {
    const vendor = await this.prisma.vendor.findUnique({
      where: { id },
      include: {
        user: { select: { name: true, email: true, phone: true, createdAt: true } },
        requestedCampus: { select: { id: true, name: true } },
      },
    });
    if (!vendor) throw new NotFoundException('Vendor not found');

    const payoutAccount = await this.payoutAccounts.findByUserId(vendor.userId).catch((err) => {
      if (err instanceof NotFoundException) return null;
      throw err;
    });

    return { ...vendor, payoutAccount };
  }

  // Task 26: campusId is optional (see ApproveVendorDto) — when given, this
  // is the one call that both approves the vendor and assigns its owning
  // user's campus, the natural "at onboarding/approval time" moment. Real
  // validation either way: requireById throws if campusId doesn't name a
  // real campus, same guarantee AdminUsersService.assignCampus gives the
  // generic path.
  async approve(adminUserId: string, id: string, campusId?: string) {
    const vendor = await this.requireVendor(id);
    if (campusId) await this.campus.requireById(campusId);

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.vendor.update({
        where: { id: vendor.id },
        data: { status: 'active', rejectionReason: null },
      });
      if (campusId) {
        await tx.user.update({ where: { id: vendor.userId }, data: { campusId } });
      }
      await this.auditLog.record(
        { actorId: adminUserId, action: 'vendor.approve', targetType: 'vendor', targetId: vendor.id, reason: campusId },
        tx,
      );
      return updated;
    });
  }

  async reject(adminUserId: string, id: string, reason: string) {
    const vendor = await this.requireVendor(id);
    if (vendor.status === 'rejected') {
      throw new ConflictException('Vendor is already rejected');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.vendor.update({
        where: { id: vendor.id },
        data: { status: 'rejected', rejectionReason: reason },
      });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'vendor.reject', targetType: 'vendor', targetId: vendor.id, reason },
        tx,
      );
      return updated;
    });
  }

  private async requireVendor(id: string) {
    const vendor = await this.prisma.vendor.findUnique({ where: { id } });
    if (!vendor) throw new NotFoundException('Vendor not found');
    return vendor;
  }
}
