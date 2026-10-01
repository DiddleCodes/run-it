import { Type } from 'class-transformer';
import { IsIn, IsInt, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export const VENDOR_SORTS = ['name', 'rating'] as const;
export type VendorSort = (typeof VENDOR_SORTS)[number];

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

export class ListVendorsQueryDto {
  @IsOptional()
  @IsString()
  category?: string;

  // Matched case-insensitively against businessName/description and the
  // names of the vendor's available menu items — see
  // VendorsService.listVendors.
  @IsOptional()
  @IsString()
  search?: string;

  // The Home screen's filter sheet. `rating` puts the best-rated first
  // (unrated vendors last); the default stays A–Z.
  @IsOptional()
  @IsIn(VENDOR_SORTS)
  sort?: VendorSort;

  // Only vendors whose real average rating is at least this. Unrated
  // vendors never match.
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(5)
  minRating?: number;

  // Only vendors with at least one available item at or under this price
  // (kobo).
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  maxPriceKobo?: number;

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
