import { IsOptional, IsString, IsUrl, MaxLength, MinLength } from 'class-validator';

// Task 30: the real student-facing "report a problem" entry point —
// same free-text reason shape as OpenDisputeDto (the admin-only
// equivalent this reuses the Dispute model with), plus an optional photo.
export class ReportProblemDto {
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;

  @IsOptional()
  @IsUrl()
  photoUrl?: string;
}
