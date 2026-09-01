import { IsString, IsUUID, Length } from 'class-validator';

export class CreatePayoutAccountDto {
  @IsUUID()
  userId!: string;

  @IsString()
  @Length(3, 10)
  bankCode!: string;

  // account_name is deliberately not accepted from the client — it is taken
  // verbatim from Paystack's resolve-account response so it can't be spoofed.
  @IsString()
  @Length(10, 10)
  accountNumber!: string;
}
