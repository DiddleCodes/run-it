import { IsOptional, IsUUID } from 'class-validator';

// Task 26: optional so an admin can still approve a vendor without
// deciding its campus in the same call (e.g. assigning it separately via
// PATCH /admin/users/:id/campus) — approval and campus assignment are two
// distinct decisions that happen to often land at the same moment, not one
// that requires the other.
export class ApproveVendorDto {
  @IsOptional()
  @IsUUID()
  campusId?: string;
}
