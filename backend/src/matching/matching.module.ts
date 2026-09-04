import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { MATCHING_QUEUE } from './matching.constants';
import { MatchingController } from './matching.controller';
import { MatchingProcessor } from './matching.processor';
import { MatchingService } from './matching.service';
import { RunnerDispatchGateway } from './runner-dispatch.gateway';

@Module({
  // CommonModule re-exports AuthModule's JwtModule — RunnerDispatchGateway
  // verifies the same JWT the REST API issues, same as NotificationsGateway.
  imports: [CommonModule, BullModule.registerQueue({ name: MATCHING_QUEUE })],
  controllers: [MatchingController],
  providers: [MatchingService, MatchingProcessor, RunnerDispatchGateway],
  // Consumed by OrderEscrowModule (claim cancels pending jobs) and
  // VendorsModule (a restaurant's "preparing" acceptance fires the initial
  // broadcast) — neither of those imports the other, so no cycle.
  exports: [MatchingService],
})
export class MatchingModule {}
