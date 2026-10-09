import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../../common/guards/admin.guard';
import { AdminAnalyticsService } from './admin-analytics.service';
import { MenuAnalyticsQueryDto } from './menu-analytics-query.dto';

@Controller('admin/analytics')
@UseGuards(AdminGuard)
export class AdminAnalyticsController {
  constructor(private readonly service: AdminAnalyticsService) {}

  @Get('menu')
  menu(@Query() query: MenuAnalyticsQueryDto) {
    return this.service.menu(query);
  }
}
