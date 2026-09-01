import { IsIn, IsNotEmpty, IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class VerifyOtpDto {
  @IsString()
  @IsNotEmpty()
  contact!: string;

  @IsString()
  @Length(6, 6)
  code!: string;

  // Restaurant/admin accounts authenticate with a password (AuthService.login)
  // — this flow is mobile student/runner signup/login only.
  @IsIn(['student', 'runner'])
  accountType!: 'student' | 'runner';

  // Only used on first verify for this contact (account creation) — a
  // returning user's already-stored name is left untouched.
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;
}
