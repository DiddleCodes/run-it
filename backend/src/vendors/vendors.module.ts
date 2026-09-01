import { Module } from '@nestjs/common';
import { MatchingModule } from '../matching/matching.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { VendorsController } from './vendors.controller';
import { VendorsService } from './vendors.service';

@Module({
  imports: [NotificationsModule, MatchingModule],
  controllers: [VendorsController],
  providers: [VendorsService],
})
export class VendorsModule {}
