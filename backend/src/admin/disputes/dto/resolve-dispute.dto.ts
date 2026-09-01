import { IsIn, IsOptional, IsString, MaxLength } from 'class-validator';

const RESOLUTION_TYPES = ['release', 'refund', 'deny'] as const;
export type DisputeResolutionInput = (typeof RESOLUTION_TYPES)[number];

export class ResolveDisputeDto {
  @IsIn(RESOLUTION_TYPES)
  resolutionType!: DisputeResolutionInput;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;
}
