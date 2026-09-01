import { Type } from 'class-transformer';
import { IsInt, IsOptional, Min } from 'class-validator';

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

export class ListNotificationsQueryDto {
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
