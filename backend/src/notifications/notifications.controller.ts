import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { RegisterDeviceTokenDto } from './dto/register-device-token.dto';
import { ListNotificationsQueryDto } from './dto/list-notifications-query.dto';
import { NotificationsService } from './notifications.service';

// Every route here is implicitly "my own" — the target is always the
// caller's own JWT sub, never a route param — so JwtAuthGuard alone is
// enough; there's no cross-user case for SelfOrAdminGuard to guard against.
@Controller('notifications')
@UseGuards(JwtAuthGuard)
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Post('device-tokens')
  registerDeviceToken(@CurrentUser() user: JwtPayload, @Body() dto: RegisterDeviceTokenDto) {
    return this.notifications.registerDeviceToken(user.sub, dto);
  }

  @Delete('device-tokens/:token')
  async removeDeviceToken(@CurrentUser() user: JwtPayload, @Param('token') token: string): Promise<{ removed: true }> {
    await this.notifications.removeDeviceToken(user.sub, token);
    return { removed: true };
  }

  @Get()
  list(@CurrentUser() user: JwtPayload, @Query() query: ListNotificationsQueryDto) {
    return this.notifications.list(user.sub, query);
  }

  @Post(':id/read')
  markRead(@CurrentUser() user: JwtPayload, @Param('id') id: string) {
    return this.notifications.markRead(user.sub, id);
  }
}
