import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminCampusService } from './admin-campus.service';
import { CreateCampusDto } from './dto/create-campus.dto';
import { UpdateCampusDto } from './dto/update-campus.dto';

@Controller('admin/campuses')
@UseGuards(AdminGuard)
export class AdminCampusController {
  constructor(private readonly service: AdminCampusService) {}

  @Get()
  list() {
    return this.service.list();
  }

  @Post()
  create(@CurrentUser() admin: JwtPayload, @Body() dto: CreateCampusDto) {
    return this.service.create(admin.sub, dto);
  }

  @Patch(':id')
  update(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: UpdateCampusDto) {
    return this.service.update(admin.sub, id, dto);
  }

  @Patch(':id/deactivate')
  deactivate(@CurrentUser() admin: JwtPayload, @Param('id') id: string) {
    return this.service.deactivate(admin.sub, id);
  }

  @Patch(':id/reactivate')
  reactivate(@CurrentUser() admin: JwtPayload, @Param('id') id: string) {
    return this.service.reactivate(admin.sub, id);
  }

  @Delete(':id')
  remove(@CurrentUser() admin: JwtPayload, @Param('id') id: string) {
    return this.service.remove(admin.sub, id);
  }
}
