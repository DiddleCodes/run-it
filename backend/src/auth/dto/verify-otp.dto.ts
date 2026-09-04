import { IsIn, IsNotEmpty, IsOptional, IsPhoneNumber, IsString, Length, MaxLength } from 'class-validator';

export class VerifyOtpDto {
  // Always an email now — both student and runner OTP contacts are (Task
  // 28 moved runner off the old phone-based path).
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

  // Task 28: runner signup only — collected alongside the (now-email)
  // contact for admin dispute-resolution contact, unrelated to OTP
  // delivery. Only used on first verify (account creation), same as
  // `name`; a returning user's already-stored phone is left untouched.
  @IsOptional()
  @IsPhoneNumber()
  phone?: string;
}
