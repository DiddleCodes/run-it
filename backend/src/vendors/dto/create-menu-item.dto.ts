import { IsBoolean, IsInt, IsOptional, IsString, IsUrl, MaxLength, Min } from 'class-validator';

export class CreateMenuItemDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  // Kobo, integer, never a float.
  @IsInt()
  @Min(1)
  price!: number;

  @IsOptional()
  @IsUrl()
  photoUrl?: string;

  @IsString()
  @MaxLength(60)
  category!: string;

  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;

  // Task 66: restaurant-set at menu-creation time — whether this item
  // counts toward Group Ordering's per-order main-meal cap. Optional,
  // defaulting to false (Prisma's column default) so an item a vendor
  // never explicitly marks (e.g. a drink, side, or dessert) never
  // accidentally counts.
  @IsOptional()
  @IsBoolean()
  isMainMeal?: boolean;
}
