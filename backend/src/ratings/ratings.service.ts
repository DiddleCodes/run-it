import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { RunnerRating, VendorRating } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RateOrderDto } from './dto/create-rating.dto';

@Injectable()
export class RatingsService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Task 48: extended from the original runner-only rating to also cover
   * the restaurant — one request can rate the runner, the vendor, or both,
   * matching the post-delivery prompt's own "rate your runner and the
   * restaurant" moment. Each party's rating is independent: rating one
   * doesn't require the other, and a duplicate on either specific party is
   * rejected (409) without silently skipping it.
   */
  async rate(orderId: string, studentUserId: string, dto: RateOrderDto): Promise<{ runner?: RunnerRating; vendor?: VendorRating }> {
    if (!dto.runner && !dto.vendor) {
      throw new BadRequestException('Provide a rating for the runner, the restaurant, or both');
    }

    const order = await this.prisma.order.findUnique({ where: { id: orderId } });
    if (!order) throw new NotFoundException('Order not found');
    if (order.studentUserId !== studentUserId) {
      throw new ForbiddenException('You may only rate your own orders');
    }
    // Task 46 set deliveredAt atomically with this status flip
    // (OrderEscrowService.release) — checking status here is equivalent to
    // checking deliveredAt != null, and matches this method's own
    // pre-existing convention.
    if (order.status !== 'delivered') {
      throw new ConflictException(`Order is ${order.status}, not delivered — nothing to rate yet`);
    }

    if (dto.runner) {
      if (!order.runnerUserId) throw new ConflictException('This order has no assigned runner to rate');
      const existing = await this.prisma.runnerRating.findUnique({ where: { orderId } });
      if (existing) throw new ConflictException('The runner has already been rated for this order');
    }
    if (dto.vendor) {
      const existing = await this.prisma.vendorRating.findUnique({ where: { orderId } });
      if (existing) throw new ConflictException('The restaurant has already been rated for this order');
    }

    return this.prisma.$transaction(async (tx) => {
      const result: { runner?: RunnerRating; vendor?: VendorRating } = {};

      if (dto.runner) {
        const runnerId = order.runnerUserId!;
        result.runner = await tx.runnerRating.create({
          data: { orderId, runnerId, studentId: studentUserId, stars: dto.runner.stars, comment: dto.runner.comment },
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
          data: { averageRating: agg._avg.stars ?? dto.runner.stars, ratingCount: agg._count.stars },
        });
      }

      if (dto.vendor) {
        const vendorId = order.vendorId;
        result.vendor = await tx.vendorRating.create({
          data: { orderId, vendorId, studentId: studentUserId, stars: dto.vendor.stars, comment: dto.vendor.comment },
        });

        const agg = await tx.vendorRating.aggregate({
          where: { vendorId },
          _avg: { stars: true },
          _count: { stars: true },
        });
        await tx.vendor.update({
          where: { id: vendorId },
          data: { averageRating: agg._avg.stars ?? dto.vendor.stars, ratingCount: agg._count.stars },
        });
      }

      return result;
    });
  }

  async summary(runnerId: string) {
    const user = await this.prisma.user.findUnique({ where: { id: runnerId } });
    if (!user) throw new NotFoundException('Runner not found');
    return { runnerId, averageRating: user.averageRating ?? 0, ratingCount: user.ratingCount };
  }

  // Task 48: the restaurant-side counterpart to summary() above — public,
  // same shape (a rating is only genuinely informational to a browsing
  // student if it's real, so this must be reachable with no auth, same
  // reasoning as the runner one).
  async vendorSummary(vendorId: string) {
    const vendor = await this.prisma.vendor.findUnique({ where: { id: vendorId } });
    if (!vendor) throw new NotFoundException('Vendor not found');
    return { vendorId, averageRating: vendor.averageRating ?? 0, ratingCount: vendor.ratingCount };
  }
}
