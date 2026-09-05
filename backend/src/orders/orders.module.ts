import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { EscrowPartyGuard } from '../common/guards/escrow-party.guard';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEscrowModule } from '../order-escrow/order-escrow.module';
import { OrdersController, OrdersHistoryController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({
  imports: [CommonModule, OrderEscrowModule, NotificationsModule],
  controllers: [OrdersController, OrdersHistoryController],
  providers: [OrdersService, EscrowPartyGuard],
})
export class OrdersModule {}
