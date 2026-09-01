import { IsDateString, IsOptional } from 'class-validator';

export class MetricsQueryDto {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
