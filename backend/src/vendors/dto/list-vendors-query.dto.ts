import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Min } from 'class-validator';

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

export class ListVendorsQueryDto {
  @IsOptional()
  @IsString()
  category?: string;

  // Matched case-insensitively against businessName/description — see
  // VendorsService.listVendors.
  @IsOptional()
  @IsString()
  search?: string;

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
