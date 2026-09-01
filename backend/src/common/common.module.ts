import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { AdminGuard } from './guards/admin.guard';
import { InternalOrAdminGuard } from './guards/internal-or-admin.guard';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { SelfOrAdminGuard } from './guards/self-or-admin.guard';

@Module({
  imports: [AuthModule],
  providers: [JwtAuthGuard, SelfOrAdminGuard, InternalOrAdminGuard, AdminGuard],
  // AuthModule is re-exported too: guards referenced by class in a consuming
  // module's @UseGuards() are instantiated within that module's own DI
  // context, so InternalOrAdminGuard's JwtService dependency must be
  // resolvable there, not just inside CommonModule itself.
  exports: [AuthModule, JwtAuthGuard, SelfOrAdminGuard, InternalOrAdminGuard, AdminGuard],
})
export class CommonModule {}
