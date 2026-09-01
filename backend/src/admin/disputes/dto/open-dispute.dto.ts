import { IsString, IsUUID, MaxLength, MinLength } from 'class-validator';

export class OpenDisputeDto {
  @IsUUID()
  orderId!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;
}
