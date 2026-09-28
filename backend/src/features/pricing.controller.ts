import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  GROUP_MAIN_MEAL_CAP,
  GROUP_ORDER_SURCHARGE_KOBO,
  STANDARD_MAIN_MEAL_CAP,
} from '../order-escrow/order-escrow.service';

// Task 70: public, read-only view of the numbers checkout prices with, so
// the Flutter app always shows exactly what OrderEscrowService.hold will
// charge — hold() rejects any fee that doesn't match these, so an app with
// its own stale copy would otherwise start failing checkout the moment an
// env value changed. Never the enforcement itself.
@Controller('pricing')
export class PricingController {
  constructor(private readonly config: ConfigService) {}

  @Get()
  get() {
    return {
      serviceFeeRate: this.config.get<number>('escrow.serviceFeeRate'),
      deliveryFeeKobo: this.config.get<number>('escrow.defaultDeliveryFeeKobo'),
      groupOrderSurchargeKobo: GROUP_ORDER_SURCHARGE_KOBO,
      standardMainMealCap: STANDARD_MAIN_MEAL_CAP,
      groupMainMealCap: GROUP_MAIN_MEAL_CAP,
    };
  }
}
