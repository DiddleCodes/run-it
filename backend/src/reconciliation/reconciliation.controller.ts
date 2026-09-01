import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { AdminGuard } from '../common/guards/admin.guard';
import { InternalOrAdminGuard } from '../common/guards/internal-or-admin.guard';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { ReconciliationReportQueryDto } from './dto/reconciliation-report-query.dto';
import { ResolveMismatchDto } from './dto/resolve-mismatch.dto';
import { ReconciliationService } from './reconciliation.service';

const DEFAULT_REPORT_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Manual trigger for an out-of-band sweep — see RUNBOOK.md. The scheduled
 * sweep (ReconciliationService.onModuleInit) already runs this on its own
 * interval; this exists for "an alert just fired, don't wait for the next
 * tick" and for smoke-testing the sweep itself.
 *
 * Task 13c adds the admin-facing read-only comparison view + run history on
 * top of this same service — not a second, parallel reconciliation system.
 */
@Controller('reconciliation')
export class ReconciliationController {
  constructor(private readonly reconciliation: ReconciliationService) {}

  @Post('run')
  @UseGuards(InternalOrAdminGuard)
  run(@CurrentUser() user: JwtPayload) {
    return this.reconciliation.runReconciliation(user.role === 'admin' ? user.sub : undefined);
  }

  @Get('report')
  @UseGuards(AdminGuard)
  report(@Query() query: ReconciliationReportQueryDto) {
    const to = query.to ? new Date(query.to) : new Date();
    const from = query.from ? new Date(query.from) : new Date(to.getTime() - DEFAULT_REPORT_WINDOW_MS);
    return this.reconciliation.compareAgainstPaystack(from, to);
  }

  @Post(':reference/resolve')
  @UseGuards(AdminGuard)
  resolve(@CurrentUser() admin: JwtPayload, @Param('reference') reference: string, @Body() dto: ResolveMismatchDto) {
    return this.reconciliation.resolveMismatch(reference, admin.sub, dto.note);
  }

  @Get('history')
  @UseGuards(AdminGuard)
  history() {
    return this.reconciliation.listRuns();
  }
}
