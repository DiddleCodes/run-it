import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, MaxLength, Min, ValidateNested } from 'class-validator';

export class RatePartyDto {
  @IsInt()
  @Min(1)
  @Max(5)
  stars!: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  comment?: string;
}

// Task 48: a student rates the runner and the restaurant independently for
// the same order — both optional so one request can carry either, both, or
// (on a client retry after a partial success) neither already-rated party.
export class RateOrderDto {
  @IsOptional()
  @ValidateNested()
  @Type(() => RatePartyDto)
  runner?: RatePartyDto;

  @IsOptional()
  @ValidateNested()
  @Type(() => RatePartyDto)
  vendor?: RatePartyDto;
}
