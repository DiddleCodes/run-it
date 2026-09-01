import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminDisputesService } from './admin-disputes.service';
import { ListDisputesQueryDto } from './dto/list-disputes-query.dto';
import { OpenDisputeDto } from './dto/open-dispute.dto';
import { ResolveDisputeDto } from './dto/resolve-dispute.dto';

@Controller('admin/disputes')
@UseGuards(AdminGuard)
export class AdminDisputesController {
  constructor(private readonly service: AdminDisputesService) {}

  @Get()
  list(@Query() query: ListDisputesQueryDto) {
    return this.service.list(query.status);
  }

  @Get(':id')
  getOne(@Param('id') id: string) {
    return this.service.getOne(id);
  }

  @Post()
  open(@CurrentUser() admin: JwtPayload, @Body() dto: OpenDisputeDto) {
    return this.service.open(admin.sub, dto);
  }

  @Post(':id/resolve')
  resolve(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: ResolveDisputeDto) {
    return this.service.resolve(admin.sub, id, dto);
  }
}
