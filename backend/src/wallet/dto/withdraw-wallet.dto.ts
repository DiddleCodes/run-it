import { IsInt, IsUUID, Min } from 'class-validator';

export class WithdrawWalletDto {
  @IsUUID()
  userId!: string;

  // Kobo, integer, never a float.
  @IsInt()
  @Min(100)
  amountKobo!: number;
}
