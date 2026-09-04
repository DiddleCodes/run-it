import { IsIn, IsNotEmpty, IsString } from 'class-validator';

export class RequestOtpDto {
  // Always an email now — both student and runner OTP contacts are (Task
  // 28 moved runner off the old phone-based path). Not validated as a
  // strict email format here (AuthService doesn't need it to be); the
  // mobile client is what enforces real email shape before submitting.
  @IsString()
  @IsNotEmpty()
  contact!: string;

  // Same accountType values verifyOtp already accepts.
  @IsIn(['student', 'runner'])
  accountType!: 'student' | 'runner';
}
