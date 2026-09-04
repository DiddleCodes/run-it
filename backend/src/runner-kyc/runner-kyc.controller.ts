import { Body, Controller, ForbiddenException, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { SubmitRunnerKycDto } from './dto/submit-runner-kyc.dto';
import { RunnerKycService } from './runner-kyc.service';

// Mirrors VendorsController's assertCanActAsVendor — same shape, scoped to
// runner accounts instead.
function assertCanActAsRunner(user: JwtPayload): void {
  if (user.role === 'admin') return;
  if (user.accountType && user.accountType !== 'runner') {
    throw new ForbiddenException('Only runner accounts may submit KYC verification');
  }
}

@Controller('runner-kyc')
export class RunnerKycController {
  constructor(private readonly runnerKyc: RunnerKycService) {}

  @Post('submit')
  @UseGuards(JwtAuthGuard)
  submit(@CurrentUser() user: JwtPayload, @Body() dto: SubmitRunnerKycDto) {
    assertCanActAsRunner(user);
    return this.runnerKyc.submit(user.sub, dto);
  }
}
