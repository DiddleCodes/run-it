import { IsOptional, IsUUID } from 'class-validator';
import { MetricsQueryDto } from '../../vendors/dto/metrics-query.dto';

export class MenuAnalyticsQueryDto extends MetricsQueryDto {
  /** Narrow to one restaurant. */
  @IsOptional()
  @IsUUID()
  vendorId?: string;
}
