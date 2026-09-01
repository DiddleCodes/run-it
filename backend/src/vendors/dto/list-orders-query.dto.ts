import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Min } from 'class-validator';

// All statuses are accepted here (not just the vendor-driven ones
// UpdateOrderStatusDto allows setting) — a vendor can filter their own
// Orders tab down to any single status, including read-only history like
// `delivered`/`cancelled`.
export const ORDER_STATUSES = [
  'placed',
  'preparing',
  'ready_for_pickup',
  'picked_up',
  'delivered',
  'cancelled',
] as const;
export type OrderStatusFilter = (typeof ORDER_STATUSES)[number];

const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;

export class ListOrdersQueryDto {
  // Omitted entirely means "the live kitchen queue" — see
  // VendorsService.listIncomingOrders's own doc comment for the exact set.
  @IsOptional()
  @IsIn(ORDER_STATUSES)
  status?: OrderStatusFilter;

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
