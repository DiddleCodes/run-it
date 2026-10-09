import { Module } from '@nestjs/common';
import { CampusModule } from '../campus/campus.module';
import { CommonModule } from '../common/common.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderEscrowModule } from '../order-escrow/order-escrow.module';
import { PayoutAccountsModule } from '../payout-accounts/payout-accounts.module';
import { AdminAuditLogService } from './admin-audit-log.service';
import { AdminCampusController } from './campus/admin-campus.controller';
import { AdminCampusService } from './campus/admin-campus.service';
import { AdminDisputesController } from './disputes/admin-disputes.controller';
import { AdminDisputesService } from './disputes/admin-disputes.service';
import { AdminPlatformMetricsController } from './platform-metrics/admin-platform-metrics.controller';
import { AdminPlatformMetricsService } from './platform-metrics/admin-platform-metrics.service';
import { AdminRunnerKycController } from './runner-kyc/admin-runner-kyc.controller';
import { AdminRunnerKycService } from './runner-kyc/admin-runner-kyc.service';
import { AdminUsersController } from './users/admin-users.controller';
import { AdminUsersService } from './users/admin-users.service';
import { AdminVendorReviewController } from './vendor-review/admin-vendor-review.controller';
import { AdminVendorReviewService } from './vendor-review/admin-vendor-review.service';
import { UploadsModule } from '../uploads/uploads.module';
import { AuthModule } from '../auth/auth.module';
import { AdminAnalyticsController } from './analytics/admin-analytics.controller';
import { AdminAnalyticsService } from './analytics/admin-analytics.service';

@Module({
  imports: [CommonModule, OrderEscrowModule, PayoutAccountsModule, NotificationsModule, CampusModule, UploadsModule, AuthModule],
  controllers: [
    AdminVendorReviewController,
    AdminDisputesController,
    AdminPlatformMetricsController,
    AdminUsersController,
    AdminRunnerKycController,
    AdminCampusController,
    AdminAnalyticsController,
  ],
  providers: [
    AdminAuditLogService,
    AdminVendorReviewService,
    AdminDisputesService,
    AdminPlatformMetricsService,
    AdminUsersService,
    AdminRunnerKycService,
    AdminCampusService,
    AdminAnalyticsService,
  ],
  exports: [AdminAuditLogService],
})
export class AdminModule {}
