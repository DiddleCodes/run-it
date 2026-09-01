import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CreateRatingDto } from './dto/create-rating.dto';
import { RatingsService } from './ratings.service';

@Controller()
export class RatingsController {
  constructor(private readonly ratings: RatingsService) {}

  // Ownership is enforced against the order itself (studentUserId), not a
  // route param — a caller can't rate an order that isn't theirs no matter
  // what orderId they pass.
  @Post('orders/:orderId/rating')
  @UseGuards(JwtAuthGuard)
  rate(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload, @Body() dto: CreateRatingDto) {
    return this.ratings.rate(orderId, user.sub, dto);
  }

  // Public — displaying a runner's rating summary needs no auth.
  @Get('runners/:id/rating-summary')
  summary(@Param('id') runnerId: string) {
    return this.ratings.summary(runnerId);
  }
}
