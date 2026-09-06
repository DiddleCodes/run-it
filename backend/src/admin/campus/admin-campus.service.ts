import { BadRequestException, ConflictException, Injectable } from '@nestjs/common';
import { CampusService } from '../../campus/campus.service';
import { PrismaService } from '../../prisma/prisma.service';
import { AdminAuditLogService } from '../admin-audit-log.service';
import { CreateCampusDto } from './dto/create-campus.dto';
import { UpdateCampusDto } from './dto/update-campus.dto';

function normalizeDomains(domains: string[]): string[] {
  const cleaned = domains.map((d) => d.trim().toLowerCase()).filter((d) => d.length > 0);
  return Array.from(new Set(cleaned));
}

@Injectable()
export class AdminCampusService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly campus: CampusService,
    private readonly auditLog: AdminAuditLogService,
  ) {}

  // Every campus, active or not — the admin list view needs to show and
  // manage both, unlike CampusService.list()'s public/signup-facing
  // active-only view. Counts are computed per campus rather than exposed
  // via Campus's own relations directly: "vendor count" means *approved,
  // active* vendors actually assigned to this campus (Vendor.user.campusId),
  // which is a different, later thing than Vendor.requestedCampusId (an
  // applicant's own stated preference at signup, see
  // AdminVendorReviewService.approve's doc comment) — counting the latter
  // would overstate a campus's real vendor presence.
  async list() {
    const campuses = await this.prisma.campus.findMany({ orderBy: { name: 'asc' } });
    return Promise.all(
      campuses.map(async (campus) => {
        const [studentCount, vendorCount] = await Promise.all([
          this.prisma.user.count({
            where: { campusId: campus.id, accountType: 'student', suspendedAt: null },
          }),
          this.prisma.vendor.count({
            where: { user: { campusId: campus.id }, status: 'active' },
          }),
        ]);
        return { ...campus, studentCount, vendorCount };
      }),
    );
  }

  async create(adminUserId: string, dto: CreateCampusDto) {
    const domains = normalizeDomains(dto.allowedEmailDomains);
    if (domains.length === 0) {
      throw new BadRequestException('At least one valid email domain is required');
    }

    return this.prisma.$transaction(async (tx) => {
      const created = await tx.campus.create({
        data: { name: dto.name.trim(), allowedEmailDomains: domains },
      });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'campus.create', targetType: 'campus', targetId: created.id, reason: created.name },
        tx,
      );
      return created;
    });
  }

  async update(adminUserId: string, id: string, dto: UpdateCampusDto) {
    await this.campus.requireById(id);

    const data: { name?: string; allowedEmailDomains?: string[] } = {};
    if (dto.name !== undefined) data.name = dto.name.trim();
    if (dto.allowedEmailDomains !== undefined) {
      const domains = normalizeDomains(dto.allowedEmailDomains);
      if (domains.length === 0) {
        throw new BadRequestException('At least one valid email domain is required');
      }
      data.allowedEmailDomains = domains;
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.campus.update({ where: { id }, data });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'campus.update', targetType: 'campus', targetId: id },
        tx,
      );
      return updated;
    });
  }

  // Soft delist: new signups against this campus's domains stop matching
  // (CampusService.resolveByEmail/list already filter on isActive), but
  // every existing user/vendor/order already tied to it keeps working —
  // nothing here touches User.campusId or any order/vendor row.
  async deactivate(adminUserId: string, id: string) {
    const campus = await this.campus.requireById(id);
    if (!campus.isActive) {
      throw new ConflictException('Campus is already inactive');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.campus.update({ where: { id }, data: { isActive: false } });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'campus.deactivate', targetType: 'campus', targetId: id },
        tx,
      );
      return updated;
    });
  }

  async reactivate(adminUserId: string, id: string) {
    const campus = await this.campus.requireById(id);
    if (campus.isActive) {
      throw new ConflictException('Campus is already active');
    }

    return this.prisma.$transaction(async (tx) => {
      const updated = await tx.campus.update({ where: { id }, data: { isActive: true } });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'campus.reactivate', targetType: 'campus', targetId: id },
        tx,
      );
      return updated;
    });
  }

  // Real hard delete — only ever allowed for a campus with zero real data
  // attached (a just-created-by-mistake row). The schema's own FKs
  // (User.campusId, Vendor.requestedCampusId) are both ON DELETE SET NULL,
  // so Postgres itself would happily null them out rather than block a
  // delete — this application-level check is the only thing standing
  // between an admin and silently orphaning real users/vendors, so it's
  // deliberately re-checked here rather than trusted to the DB.
  async remove(adminUserId: string, id: string) {
    await this.campus.requireById(id);

    const [userCount, requestedByVendorCount] = await Promise.all([
      this.prisma.user.count({ where: { campusId: id } }),
      this.prisma.vendor.count({ where: { requestedCampusId: id } }),
    ]);
    if (userCount > 0 || requestedByVendorCount > 0) {
      throw new ConflictException(
        `Can't delete: ${userCount} user(s) and ${requestedByVendorCount} vendor application(s) still reference this campus. Deactivate it instead.`,
      );
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.campus.delete({ where: { id } });
      await this.auditLog.record(
        { actorId: adminUserId, action: 'campus.delete', targetType: 'campus', targetId: id },
        tx,
      );
    });

    return { id, deleted: true };
  }
}
