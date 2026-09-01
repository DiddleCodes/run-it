import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { AdminGuard } from '../../common/guards/admin.guard';
import { MetricsQueryDto } from '../../vendors/dto/metrics-query.dto';
import { AdminPlatformMetricsService } from './admin-platform-metrics.service';

@Controller('admin/metrics')
@UseGuards(AdminGuard)
export class AdminPlatformMetricsController {
  constructor(private readonly service: AdminPlatformMetricsService) {}

  @Get()
  metrics(@Query() query: MetricsQueryDto) {
    return this.service.metrics(query);
  }
}
