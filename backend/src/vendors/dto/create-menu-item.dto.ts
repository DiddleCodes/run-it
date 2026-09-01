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
}
