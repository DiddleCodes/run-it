import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { RunnerKycStatus } from '@prisma/client';

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

const RUNNER_KYC_STATUSES: RunnerKycStatus[] = ['pending', 'approved', 'rejected'];

export class ListAdminRunnerKycQueryDto {
  // No filter = every status, mirrors ListAdminVendorsQueryDto's own
  // "All" tab convention.
  @IsOptional()
  @IsIn(RUNNER_KYC_STATUSES)
  status?: RunnerKycStatus;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  limit?: number;
}

export { DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE };
