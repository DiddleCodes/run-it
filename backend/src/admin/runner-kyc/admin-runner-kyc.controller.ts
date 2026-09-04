import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminRunnerKycService } from './admin-runner-kyc.service';
import { ListAdminRunnerKycQueryDto } from './dto/list-admin-runner-kyc-query.dto';
import { RejectRunnerKycDto } from './dto/reject-runner-kyc.dto';

@Controller('admin/runner-kyc')
@UseGuards(AdminGuard)
export class AdminRunnerKycController {
  constructor(private readonly service: AdminRunnerKycService) {}

  @Get()
  list(@Query() query: ListAdminRunnerKycQueryDto) {
    return this.service.list(query);
  }

  @Get(':id')
  getOne(@Param('id') id: string) {
    return this.service.getOne(id);
  }

  @Post(':id/approve')
  approve(@CurrentUser() admin: JwtPayload, @Param('id') id: string) {
    return this.service.approve(admin.sub, id);
  }

  @Post(':id/reject')
  reject(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: RejectRunnerKycDto) {
    return this.service.reject(admin.sub, id, dto.reason);
  }
}
