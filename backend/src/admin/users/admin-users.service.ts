import { Injectable, NotFoundException } from '@nestjs/common';
import { AccountType } from '@prisma/client';
import { NotificationsEmitterService } from '../../notifications/notifications-emitter.service';
import { PrismaService } from '../../prisma/prisma.service';
import { AdminAuditLogService } from '../admin-audit-log.service';
import { DEFAULT_PAGE_SIZE, ListAdminUsersQueryDto, MAX_PAGE_SIZE } from './dto/list-admin-users-query.dto';

// Never returns User.password — every query below is an explicit `select`,
// not `include`, specifically so a hash can never accidentally round-trip
// to the dashboard.
const USER_SELECT = {
  id: true,
  email: true,
  phone: true,
  name: true,
  accountType: true,
  suspendedAt: true,
  createdAt: true,
} as const;

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AdminAuditLogService,
    private readonly notifications: NotificationsEmitterService,
  ) {}

  async list(query: ListAdminUsersQueryDto) {
    const page = query.page ?? 1;
    const limit = Math.min(query.limit ?? DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE);
    const search = query.search?.trim();

    const where = {
      ...(query.accountType ? { accountType: query.accountType } : {}),
      ...(search
        ? {
            OR: [
              { name: { contains: search, mode: 'insensitive' as const } },
              { email: { contains: search, mode: 'insensitive' as const } },
              { phone: { contains: search, mode: 'insensitive' as const } },
            ],
          }
        : {}),
    };

    const [items, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        select: USER_SELECT,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.user.count({ where }),
    ]);

    return { items, total, page, limit };
  }

  // + vendor row if restaurant, + wallet balance if student/runner — both
  // relations are optional on User, so this reads the same regardless of
  // accountType and simply comes back null for the non-applicable one.
  async getOne(id: string) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        ...USER_SELECT,
        vendor: { select: { id: true, businessName: true, status: true } },
        wallet: { select: { balance: true } },
      },
    });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async suspend(adminUserId: string, id: string, reason: string) {
    const user = await this.requireUser(id);

    const updated = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.user.update({ where: { id: user.id }, data: { suspendedAt: new Date() }, select: USER_SELECT });

      // Cascade: a suspended restaurant's Vendor flips to inactive, which
      // VendorsService.listVendors already filters out of student browsing
      // (Task 14) — no separate filtering logic needed, verified by test.
      if (user.accountType === 'restaurant') {
        await tx.vendor.updateMany({ where: { userId: user.id }, data: { status: 'inactive' } });
      }

      await this.auditLog.record(
        { actorId: adminUserId, action: 'user.suspend', targetType: 'user', targetId: user.id, reason },
        tx,
      );
      return updated;
    });

    this.notifications.emit({
      type: 'account_suspended',
      recipientUserId: user.id,
      title: 'Account suspended',
      body: reason ? `Your account has been suspended: ${reason}` : 'Your account has been suspended.',
      data: { userId: user.id },
    });

    return updated;
  }

  // Reinstating the person does NOT auto-reactivate a suspended vendor —
  // that's a separate decision, made through the normal vendor-review
  // approve action.
  async reinstate(adminUserId: string, id: string) {
    const user = await this.requireUser(id);

    const updated = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.user.update({ where: { id: user.id }, data: { suspendedAt: null }, select: USER_SELECT });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'user.reinstate', targetType: 'user', targetId: user.id },
        tx,
      );
      return updated;
    });

    this.notifications.emit({
      type: 'account_reinstated',
      recipientUserId: user.id,
      title: 'Account reinstated',
      body: 'Your account has been reinstated. You can now log in again.',
      data: { userId: user.id },
    });

    return updated;
  }

  private async requireUser(id: string): Promise<{ id: string; accountType: AccountType }> {
    const user = await this.prisma.user.findUnique({ where: { id }, select: { id: true, accountType: true } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }
}
