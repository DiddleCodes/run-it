import { IsString, Length } from 'class-validator';

export class VerifyCodeDto {
  // 4-6 digits, accepted as a string (not a number) so a leading zero can't
  // silently get dropped by a client's JSON encoder.
  @IsString()
  @Length(4, 6)
  code!: string;
}
