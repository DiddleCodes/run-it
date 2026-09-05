import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { RateOrderDto } from './dto/create-rating.dto';
import { RatingsService } from './ratings.service';

@Controller()
export class RatingsController {
  constructor(private readonly ratings: RatingsService) {}

  // Ownership is enforced against the order itself (studentUserId), not a
  // route param — a caller can't rate an order that isn't theirs no matter
  // what orderId they pass. Task 48: now rates the runner, the restaurant,
  // or both in one call — see RatingsService.rate's own doc comment.
  @Post('orders/:orderId/rating')
  @UseGuards(JwtAuthGuard)
  rate(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload, @Body() dto: RateOrderDto) {
    return this.ratings.rate(orderId, user.sub, dto);
  }

  // Public — displaying a runner's rating summary needs no auth.
  @Get('runners/:id/rating-summary')
  summary(@Param('id') runnerId: string) {
    return this.ratings.summary(runnerId);
  }

  // Task 48: public — a rating is only genuinely informational to a
  // student browsing restaurants if it's reachable with no auth, same as
  // the runner one above.
  @Get('vendors/:id/rating-summary')
  vendorSummary(@Param('id') vendorId: string) {
    return this.ratings.vendorSummary(vendorId);
  }
}
