import { Module } from '@nestjs/common';
import { CampusModule } from '../campus/campus.module';
import { MatchingModule } from '../matching/matching.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEscrowModule } from '../order-escrow/order-escrow.module';
import { VendorsController } from './vendors.controller';
import { VendorsService } from './vendors.service';

@Module({
  imports: [NotificationsModule, MatchingModule, CampusModule, OrderEscrowModule],
  controllers: [VendorsController],
  providers: [VendorsService],
})
export class VendorsModule {}
