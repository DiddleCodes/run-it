import { IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';

export class UpsertVendorDto {
  @IsString()
  @MaxLength(120)
  businessName!: string;

  @IsString()
  @MaxLength(60)
  category!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsUrl()
  logoUrl?: string;
}
