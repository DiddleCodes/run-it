import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Min } from 'class-validator';
import { AccountType } from '@prisma/client';

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

const ACCOUNT_TYPES: AccountType[] = ['student', 'runner', 'restaurant', 'admin'];

export class ListAdminUsersQueryDto {
  // Matched case-insensitively against name/email/phone — see
  // AdminUsersService.list.
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsIn(ACCOUNT_TYPES)
  accountType?: AccountType;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  limit?: number;
}

export { DEFAULT_PAGE_SIZE, MAX_PAGE_SIZE };
