import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

/**
 * One generic audit trail shared by every admin mutation. `record()` takes an
 * optional Prisma transaction client (`tx`) so callers write the audit row
 * inside the same transaction as the mutation it describes — an entry can
 * never exist without its action having actually committed, or vice versa.
 */
@Injectable()
export class AdminAuditLogService {
  constructor(private readonly prisma: PrismaService) {}

  async record(
    params: {
      actorId: string;
      action: string;
      targetType: string;
      targetId: string;
      reason?: string;
    },
    tx?: Prisma.TransactionClient,
  ): Promise<void> {
    const client = tx ?? this.prisma;
    await client.adminAuditLog.create({
      data: {
        actorId: params.actorId,
        action: params.action,
        targetType: params.targetType,
        targetId: params.targetId,
        reason: params.reason,
      },
    });
  }
}
