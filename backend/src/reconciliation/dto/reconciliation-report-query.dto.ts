import { IsDateString, IsOptional } from 'class-validator';

export class ReconciliationReportQueryDto {
  @IsOptional()
  @IsDateString()
  from?: string;

  @IsOptional()
  @IsDateString()
  to?: string;
}
