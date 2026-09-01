import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { EscrowPartyGuard } from '../common/guards/escrow-party.guard';
import { MatchingModule } from '../matching/matching.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { PaystackModule } from '../paystack/paystack.module';
import { OrderEscrowController } from './order-escrow.controller';
import { OrderEscrowService } from './order-escrow.service';

@Module({
  imports: [PaystackModule, CommonModule, NotificationsModule, MatchingModule],
  controllers: [OrderEscrowController],
  providers: [OrderEscrowService, EscrowPartyGuard],
  exports: [OrderEscrowService],
})
export class OrderEscrowModule {}
