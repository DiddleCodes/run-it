import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export const ORDER_PAYMENT_METHODS = ['wallet', 'pay_on_delivery'] as const;
export type OrderPaymentMethodInput = (typeof ORDER_PAYMENT_METHODS)[number];

// Task 66: single device/payer/restaurant "Group Order" mode.
export const ORDER_TYPES = ['standard', 'group'] as const;
export type OrderTypeInput = (typeof ORDER_TYPES)[number];

export class OrderItemInputDto {
  // Task 70: required — the menu item is the only thing hold() trusts. Its
  // real name and price are re-read from the database (and snapshotted onto
  // the OrderItem row from there); the name/price below are the client's
  // own echo of what it displayed, accepted for wire compatibility and
  // never used for money.
  @IsUUID()
  menuItemId!: string;

  @IsOptional()
  @IsString()
  name?: string;

  // Kobo, integer, never a float. Ignored for pricing (see above).
  @IsOptional()
  @IsInt()
  @Min(1)
  priceKobo?: number;

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
  // below) — kept named grossAmountKobo for wire compatibility.
  // Task 70: the client's claim of what it showed, never the amount
  // charged — hold() re-derives the real subtotal from database prices and
  // rejects (409) a claim that doesn't match, so a student is never
  // charged anything other than what they were shown. Optional: omitting
  // it just skips that comparison.
  @IsOptional()
  @IsInt()
  @Min(1)
  grossAmountKobo?: number;

  // Kobo, integer, never a float. Task 15: a separate line item from the
  // food subtotal above, never subject to restaurant commission. Optional
  // so the not-yet-updated Flutter client (which omits it) still works —
  // hold() falls back to the configured DEFAULT_DELIVERY_FEE when omitted.
  // Task 45: now a single flat fee (no more zone tiers), and 100% platform
  // revenue — see commission.util.ts.
  // Task 70: server-authoritative — anything other than the configured
  // flat fee is rejected (400), never charged. Always the BASE fee; a
  // group order's surcharge is added by hold() itself.
  @IsOptional()
  @IsInt()
  @Min(0)
  deliveryFeeKobo?: number;

  // Kobo, integer, never a float. Task 45: a separate line item from the
  // food subtotal, same spirit as deliveryFeeKobo above — never subject to
  // restaurant commission, flows 100% to platform revenue.
  // Task 70: now SERVICE_FEE_RATE (5%) of the server-derived food subtotal,
  // computed by hold() itself — a value that doesn't match is rejected
  // (400), never charged. Optional: omitting it just skips the comparison.
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

  // Task 47: how the student chose to pay at checkout. Optional, defaulting
  // to 'wallet' — every already-shipped Flutter client omits this and must
  // keep behaving exactly as before. 'pay_on_delivery' skips the wallet
  // debit entirely; hold() re-validates the vendor's own opt-in and the
  // order-value cap server-side regardless of what the client already
  // checked (see OrderEscrowService.hold's own doc comment).
  @IsOptional()
  @IsIn(ORDER_PAYMENT_METHODS)
  paymentMethod?: OrderPaymentMethodInput;

  // Task 66: 'group' raises the per-order main-meal cap (2 -> 4) and adds
  // a flat surcharge to the delivery fee. Optional, defaulting to
  // 'standard' — an old caller that omits it keeps today's exact behavior.
  // Choosing 'group' itself is never the abuse vector (it costs more and
  // caps out at 4 either way) — the real enforcement is that hold()
  // re-derives every item's isMainMeal from the database by menuItemId,
  // never from this payload's item name/price, so a direct API call can't
  // stay 'standard' while smuggling a 3rd/4th main meal past the cap.
  @IsOptional()
  @IsIn(ORDER_TYPES)
  orderType?: OrderTypeInput;

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

  // Task 70: required — the food subtotal (and so every fee and payout)
  // is computed from these items' real database prices.
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => OrderItemInputDto)
  items!: OrderItemInputDto[];
}
