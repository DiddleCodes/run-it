import { Body, Controller, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AdminGuard } from '../../common/guards/admin.guard';
import { JwtPayload } from '../../auth/jwt-payload.interface';
import { AdminVendorReviewService } from './admin-vendor-review.service';
import { ListAdminVendorsQueryDto } from './dto/list-admin-vendors-query.dto';
import { RejectVendorDto } from './dto/reject-vendor.dto';

@Controller('admin/vendors')
@UseGuards(AdminGuard)
export class AdminVendorReviewController {
  constructor(private readonly service: AdminVendorReviewService) {}

  @Get()
  list(@Query() query: ListAdminVendorsQueryDto) {
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
  reject(@CurrentUser() admin: JwtPayload, @Param('id') id: string, @Body() dto: RejectVendorDto) {
    return this.service.reject(admin.sub, id, dto.reason);
  }
}
