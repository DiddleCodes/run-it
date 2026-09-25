import { Transform } from 'class-transformer';
import { IsIn, IsNotEmpty, IsString, MaxLength, ValidateIf } from 'class-validator';

// Task 61: mirrors the OrderDeclineReason Prisma enum.
export const ORDER_DECLINE_REASONS = ['out_of_stock', 'kitchen_closed', 'too_busy', 'other'] as const;
export type OrderDeclineReasonInput = (typeof ORDER_DECLINE_REASONS)[number];

export class DeclineOrderDto {
  @IsIn(ORDER_DECLINE_REASONS)
  reason!: OrderDeclineReasonInput;

  // Free text, required only for 'other' (and ignored for every other
  // reason — VendorsService.declineOrder never persists it for those).
  // Trimmed first so a whitespace-only "reason" can't satisfy IsNotEmpty.
  @ValidateIf((o) => o.reason === 'other')
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @IsNotEmpty({ message: 'Tell the student why when choosing "Other"' })
  @MaxLength(280)
  note?: string;
}
