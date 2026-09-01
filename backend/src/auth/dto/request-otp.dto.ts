import { IsIn, IsNotEmpty, IsString } from 'class-validator';

export class RequestOtpDto {
  // Email or phone — whichever the mobile client collected. Not validated
  // as strictly one or the other here; accountType (below) is what tells
  // requestOtp which one it is.
  @IsString()
  @IsNotEmpty()
  contact!: string;

  // Task 20: needed so requestOtp knows whether `contact` is an email
  // (student — real Brevo delivery) or a phone number (runner — no
  // delivery channel yet, SMS is a future task) before it can decide how
  // to send the code. Same accountType values verifyOtp already accepts.
  @IsIn(['student', 'runner'])
  accountType!: 'student' | 'runner';
}
