import { Type } from 'class-transformer';
import {
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class OrderItemInputDto {
  // Nullable on the created row too — the menu item this pointed at may
  // since have been edited or deleted; name/price are snapshotted below
  // regardless.
  @IsOptional()
  @IsUUID()
  menuItemId?: string;

  @IsString()
  name!: string;

  // Kobo, integer, never a float.
  @IsInt()
  @Min(1)
  priceKobo!: number;

  @IsInt()
  @Min(1)
  quantity!: number;
}

export class HoldEscrowDto {
  @IsUUID()
  studentUserId!: string;

  @IsUUID()
  restaurantUserId!: string;

  // Task 21a: optional — a broadcast-and-claim order can be held with no
  // runner attached yet. Omitted entirely by the (not-yet-updated) Flutter
  // client, which still resolves a runner up front; the real matching flow
  // now works with this left unset too.
  @IsOptional()
  @IsUUID()
  runnerUserId?: string;

  // Kobo, integer, never a float. Despite the name, this is the food
  // subtotal only as of Task 15 (delivery fee is now a separate line item
  // below) — kept named grossAmountKobo for wire compatibility with the
  // Flutter client, which doesn't yet distinguish the two.
  @IsInt()
  @Min(1)
  grossAmountKobo!: number;

  // Kobo, integer, never a float. Task 15: a separate line item from the
  // food subtotal above, never subject to restaurant commission. Optional
  // so the not-yet-updated Flutter client (which omits it) still works —
  // hold() falls back to the configured DEFAULT_DELIVERY_FEE when omitted.
  // Task 45: now a single flat fee (no more zone tiers), and 100% platform
  // revenue — see commission.util.ts.
  @IsOptional()
  @IsInt()
  @Min(0)
  deliveryFeeKobo?: number;

  // Kobo, integer, never a float. Task 45: a separate line item from the
  // food subtotal, same spirit as deliveryFeeKobo above — never subject to
  // restaurant commission, flows 100% to platform revenue. Optional so an
  // old caller that omits it still works (defaults to 0).
  @IsOptional()
  @IsInt()
  @Min(0)
  serviceFeeKobo?: number;

  // Task 45: replaces the old per-item OrderItem.notes — a single note for
  // the whole order, e.g. a delivery instruction for the runner or a
  // customization request for the restaurant.
  @IsOptional()
  @IsString()
  @MaxLength(280)
  note?: string;

  // Task 9: identifies which Vendor row this order belongs to. Optional so
  // the already-shipped Flutter client (which doesn't send it) keeps
  // working — hold() falls back to resolving/auto-provisioning a Vendor
  // from restaurantUserId when omitted.
  @IsOptional()
  @IsUUID()
  vendorId?: string;

  @IsOptional()
  @IsString()
  deliveryLocationLabel?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => OrderItemInputDto)
  items?: OrderItemInputDto[];
}
