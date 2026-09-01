import { BullModule } from '@nestjs/bullmq';
import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { FCM_PUSH_QUEUE } from './notifications.constants';
import { NotificationsController } from './notifications.controller';
import { NotificationsGateway } from './notifications.gateway';
import { NotificationsService } from './notifications.service';
import { NotificationsEmitterService } from './notifications-emitter.service';
import { FcmService } from './fcm.service';
import { FcmProcessor } from './fcm.processor';

@Module({
  // CommonModule brings in JwtAuthGuard (controller) and, via its own
  // re-export of AuthModule, JwtService (the gateway's own handshake
  // verification — same secret, same payload shape as the REST API's
  // JwtAuthGuard, just checked by hand at connect time instead of through
  // Passport).
  imports: [CommonModule, BullModule.registerQueue({ name: FCM_PUSH_QUEUE })],
  controllers: [NotificationsController],
  providers: [NotificationsService, NotificationsEmitterService, NotificationsGateway, FcmService, FcmProcessor],
  // NotificationsEmitterService is what every trigger-point module (order
  // escrow, vendors, orders, admin users) actually imports this module for.
  exports: [NotificationsEmitterService],
})
export class NotificationsModule {}
