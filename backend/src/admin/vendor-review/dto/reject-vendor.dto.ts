import { IsString, MaxLength, MinLength } from 'class-validator';

export class RejectVendorDto {
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;
}
