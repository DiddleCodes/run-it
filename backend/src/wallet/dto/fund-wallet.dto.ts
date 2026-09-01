import { IsEmail, IsInt, IsUUID, Min } from 'class-validator';

export class FundWalletDto {
  @IsUUID()
  userId!: string;

  @IsEmail()
  email!: string;

  // Kobo, integer, never a float.
  @IsInt()
  @Min(100)
  amountKobo!: number;
}
