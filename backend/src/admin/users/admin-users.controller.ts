import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminUsersService } from './admin-users.service';
import { AssignCampusDto } from './dto/assign-campus.dto';
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

  // Task 26: the admin-assignment mechanism for a restaurant/runner's
  // campus (see AdminUsersService.assignCampus's own doc comment for why
  // it lives here rather than a dedicated onboarding flow).
  @Patch(':id/campus')
  assignCampus(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: AssignCampusDto) {
    return this.service.assignCampus(admin.sub, id, dto.campusId);
  }
}
