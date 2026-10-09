import { IsOptional, IsString, MaxLength, MinLength } from 'class-validator';
import { IsPrivateFileRef } from '../../uploads/private-files';

// Task 30: the real student-facing "report a problem" entry point —
// same free-text reason shape as OpenDisputeDto (the admin-only
// equivalent this reuses the Dispute model with), plus an optional photo.
export class ReportProblemDto {
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason!: string;

  // A private-bucket reference from POST /uploads/presign — the student's own upload.
  @IsOptional()
  @IsPrivateFileRef('dispute-report')
  photoUrl?: string;
}
