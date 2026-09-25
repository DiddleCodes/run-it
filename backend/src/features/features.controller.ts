import { Controller, Get } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// Task 67: public, read-only view of the platform-wide feature switches in
// configuration.ts's `features` block — lets the Flutter app hide a
// globally-disabled feature entirely instead of offering something the
// server would reject. Never the enforcement itself; that stays in each
// feature's own service (e.g. OrderEscrowService.hold for POD).
@Controller('features')
export class FeaturesController {
  constructor(private readonly config: ConfigService) {}

  @Get()
  get() {
    return { podEnabled: this.config.get<boolean>('features.podEnabled') === true };
  }
}
