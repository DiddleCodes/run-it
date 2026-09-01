import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEscrowModule } from '../order-escrow/order-escrow.module';
import { PayoutAccountsModule } from '../payout-accounts/payout-accounts.module';
import { AdminAuditLogService } from './admin-audit-log.service';
import { AdminDisputesController } from './disputes/admin-disputes.controller';
import { AdminDisputesService } from './disputes/admin-disputes.service';
import { AdminPlatformMetricsController } from './platform-metrics/admin-platform-metrics.controller';
import { AdminPlatformMetricsService } from './platform-metrics/admin-platform-metrics.service';
import { AdminUsersController } from './users/admin-users.controller';
import { AdminUsersService } from './users/admin-users.service';
import { AdminVendorReviewController } from './vendor-review/admin-vendor-review.controller';
import { AdminVendorReviewService } from './vendor-review/admin-vendor-review.service';

@Module({
  imports: [CommonModule, OrderEscrowModule, PayoutAccountsModule, NotificationsModule],
  controllers: [AdminVendorReviewController, AdminDisputesController, AdminPlatformMetricsController, AdminUsersController],
  providers: [
    AdminAuditLogService,
    AdminVendorReviewService,
    AdminDisputesService,
    AdminPlatformMetricsService,
    AdminUsersService,
  ],
  exports: [AdminAuditLogService],
})
export class AdminModule {}
