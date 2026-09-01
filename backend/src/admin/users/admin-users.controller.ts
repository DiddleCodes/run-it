import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminUsersService } from './admin-users.service';
import { ListAdminUsersQueryDto } from './dto/list-admin-users-query.dto';
import { SuspendUserDto } from './dto/suspend-user.dto';

@Controller('admin/users')
@UseGuards(AdminGuard)
export class AdminUsersController {
  constructor(private readonly service: AdminUsersService) {}

  @Get()
  list(@Query() query: ListAdminUsersQueryDto) {
    return this.service.list(query);
  }

  @Get(':id')
  getOne(@Param('id') id: string) {
    return this.service.getOne(id);
  }

  @Post(':id/suspend')
  suspend(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: SuspendUserDto) {
    return this.service.suspend(admin.sub, id, dto.reason);
  }

  @Post(':id/reinstate')
  reinstate(@CurrentUser() admin: JwtPayload, @Param('id') id: string) {
    return this.service.reinstate(admin.sub, id);
  }
}
