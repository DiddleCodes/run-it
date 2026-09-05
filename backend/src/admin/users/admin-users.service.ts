import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { AccountType } from '@prisma/client';
import { CampusService } from '../../campus/campus.service';
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
  campusId: true,
  // Task 48: useful context for admin review (a runner-KYC decision, a
  // support conversation) — real for any account type that's ever been
  // rated, meaningless (null/0) for the rest.
  averageRating: true,
  ratingCount: true,
} as const;

@Injectable()
export class AdminUsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auditLog: AdminAuditLogService,
    private readonly notifications: NotificationsEmitterService,
    private readonly campus: CampusService,
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
  //
  // Task 47: + a runner's real outstanding Pay on Delivery cash debt — this
  // is genuine platform financial exposure (the platform already funded
  // that runner's restaurant/delivery payouts up front), so it belongs on
  // the same admin surface as a wallet balance rather than buried in the
  // orders/disputes lists. Only computed for a runner; null otherwise.
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

    const outstandingCashDebtKobo =
      user.accountType === 'runner' ? await this.sumOutstandingCashDebt(id) : null;

    return { ...user, outstandingCashDebtKobo };
  }

  // Task 47: a deliberately simple, manual reconciliation action — settles
  // every one of this runner's currently-outstanding (pending or disputed)
  // cash debts at once, rather than building a per-debt settlement UI or an
  // automatic netting-against-wallet-earnings job. An admin calls this once
  // they've confirmed, by whatever real-world means, that the runner has
  // actually remitted the cash they owed.
  async settleCashDebt(adminUserId: string, id: string) {
    const user = await this.requireUser(id);
    if (user.accountType !== 'runner') {
      throw new BadRequestException('Only runner accounts can carry a cash-collection debt');
    }

    const settled = await this.prisma.$transaction(async (tx) => {
      const result = await tx.cashCollectionDebt.updateMany({
        where: { runnerId: id, status: { in: ['pending', 'disputed'] } },
        data: { status: 'settled', settledAt: new Date(), settledBy: adminUserId },
      });
      await this.auditLog.record(
        {
          actorId: adminUserId,
          action: 'user.settle_cash_debt',
          targetType: 'user',
          targetId: id,
          reason: `Settled ${result.count} outstanding cash-collection debt(s)`,
        },
        tx,
      );
      return result.count;
    });

    return { runnerId: id, settledCount: settled, outstandingCashDebtKobo: await this.sumOutstandingCashDebt(id) };
  }

  private async sumOutstandingCashDebt(runnerId: string): Promise<number> {
    const result = await this.prisma.cashCollectionDebt.aggregate({
      where: { runnerId, status: { in: ['pending', 'disputed'] } },
      _sum: { amountOwed: true },
    });
    return result._sum.amountOwed ?? 0;
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

      // Task 34: revoke every live refresh token this user holds.
      // AuthService.refresh already re-checks suspendedAt directly on
      // every call, so this isn't the only thing standing between a
      // suspended user and a fresh access token — but it closes the token
      // itself immediately rather than leaving a live, merely-unusable
      // credential lying around, same defense-in-depth spirit as
      // JwtStrategy's own per-request suspension check (Task 17).
      await tx.refreshToken.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: new Date() },
      });

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

  // Task 26: the actual admin-assignment mechanism for a restaurant or
  // runner's campus — there was no runner onboarding/KYC-review flow of
  // any shape in this backend to hang this off of (see the Task 26
  // investigation report), so this lives on the one admin surface that
  // already manages every account type generically. Deliberately not
  // restricted to restaurant/runner accountType: a student's campus is
  // normally derived, never picked, but an admin overriding a
  // mis-derived one (e.g. a school that later gets a second valid email
  // domain added) is a legitimate support action, not a bypass of the
  // signup-time enforcement itself.
  async assignCampus(adminUserId: string, id: string, campusId: string) {
    const user = await this.requireUser(id);
    if (user.accountType === 'admin') {
      throw new BadRequestException('Admin accounts are never campus-scoped');
    }
    await this.campus.requireById(campusId);

    const updated = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.user.update({ where: { id: user.id }, data: { campusId }, select: USER_SELECT });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'user.assign_campus', targetType: 'user', targetId: user.id, reason: campusId },
        tx,
      );
      return updated;
    });

    return updated;
  }

  private async requireUser(id: string): Promise<{ id: string; accountType: AccountType }> {
    const user = await this.prisma.user.findUnique({ where: { id }, select: { id: true, accountType: true } });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }
}
