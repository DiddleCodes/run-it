import { IsInt, IsOptional, IsString, Length, Min } from 'class-validator';

export class VerifyCodeDto {
  // 4-6 digits, accepted as a string (not a number) so a leading zero can't
  // silently get dropped by a client's JSON encoder.
  @IsString()
  @Length(4, 6)
  code!: string;

  // Task 47: the runner's "mark as paid" confirmation, bundled into the
  // same delivery-verification call rather than a separate endpoint a
  // runner could skip — a Pay on Delivery order can't reach `delivered`
  // without it (see OrdersService.verifyDelivery's own doc comment).
  // Meaningless (and ignored) for a wallet order.
  @IsOptional()
  @IsInt()
  @Min(0)
  amountCollectedKobo?: number;
}
