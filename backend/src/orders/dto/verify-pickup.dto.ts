import { IsString, IsUrl, Length } from 'class-validator';

// Task 30: the handoff photo is required, not optional — see
// Order.handoffPhotoUrl's schema doc comment for why this is a hard
// block (a 400 here, before the code is ever checked) rather than a
// soft/loggable warning. Separate from VerifyCodeDto (which
// verify-delivery still uses alone) since delivery has no equivalent
// photo requirement.
export class VerifyPickupDto {
  // 4-6 digits, accepted as a string (not a number) so a leading zero
  // can't silently get dropped by a client's JSON encoder.
  @IsString()
  @Length(4, 6)
  code!: string;

  @IsUrl()
  handoffPhotoUrl!: string;
}
