import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { RunnerRating } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { CreateRatingDto } from './dto/create-rating.dto';

@Injectable()
export class RatingsService {
  constructor(private readonly prisma: PrismaService) {}

  async rate(orderId: string, studentUserId: string, dto: CreateRatingDto): Promise<RunnerRating> {
    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (order.studentUserId !== studentUserId) {
      throw new ForbiddenException('You may only rate your own orders');
    }
    if (order.status !== 'delivered') {
      throw new ConflictException(`Order is ${order.status}, not delivered — nothing to rate yet`);
    }
    if (!order.runnerUserId) {
      throw new ConflictException('This order has no assigned runner to rate');
    }

    const existing = await this.prisma.runnerRating.findUnique({ where: { orderId } });
    if (existing) throw new ConflictException('This order has already been rated');

    const runnerId = order.runnerUserId;

    return this.prisma.$transaction(async (tx) => {
      const rating = await tx.runnerRating.create({
        data: { orderId, runnerId, studentId: studentUserId, stars: dto.stars, comment: dto.comment },
      });

      // Recalculated from the ledger on every write rather than a DB
      // trigger, matching this codebase's existing style of doing
      // reconciliation in application code (see webhooks.service.ts).
      const agg = await tx.runnerRating.aggregate({
        where: { runnerId },
        _avg: { stars: true },
        _count: { stars: true },
      });

      await tx.user.update({
        where: { id: runnerId },
        data: {
          averageRating: agg._avg.stars ?? dto.stars,
          ratingCount: agg._count.stars,
        },
      });

      return rating;
    });
  }

  async summary(runnerId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: runnerId } });
    if (!user) throw new NotFoundException('Runner not found');
    return { runnerId, averageRating: user.averageRating ?? 0, ratingCount: user.ratingCount };
  }
}
