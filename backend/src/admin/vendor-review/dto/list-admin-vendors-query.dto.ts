import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Min } from 'class-validator';
import { VendorStatus } from '@prisma/client';

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

const VENDOR_STATUSES: VendorStatus[] = ['pending', 'active', 'rejected', 'inactive'];

export class ListAdminVendorsQueryDto {
  // No filter = every status, so the queue's "All" tab can reuse this same
  // endpoint rather than needing a second unfiltered route.
  @IsOptional()
  @IsIn(VENDOR_STATUSES)
  status?: VendorStatus;

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
