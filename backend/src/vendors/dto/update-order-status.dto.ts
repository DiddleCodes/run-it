import { IsIn } from 'class-validator';

// Deliberately narrower than the full OrderStatus enum — a vendor may only
// ever push their own order forward through these two steps. Every later
// transition (picked_up, delivered) is runner/delivery-driven (Task 11);
// placed/cancelled are set by escrow hold/refund, never by this endpoint.
export const VENDOR_DRIVEN_STATUSES = ['preparing', 'ready_for_pickup'] as const;
export type VendorDrivenStatus = (typeof VENDOR_DRIVEN_STATUSES)[number];

export class UpdateOrderStatusDto {
  @IsIn(VENDOR_DRIVEN_STATUSES)
  status!: VendorDrivenStatus;
}
