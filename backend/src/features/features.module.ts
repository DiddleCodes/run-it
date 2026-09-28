import { Module } from '@nestjs/common';
import { FeaturesController } from './features.controller';
import { PricingController } from './pricing.controller';

@Module({
  // Public, read-only client config: platform switches (Task 67) and
  // checkout pricing (Task 70).
  controllers: [FeaturesController, PricingController],
})
export class FeaturesModule {}
