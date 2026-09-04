import { Controller, Get, UseGuards } from '@nestjs/common';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { MatchingService } from './matching.service';

@Controller('matching')
export class MatchingController {
  constructor(private readonly matching: MatchingService) {}

  // Task 21b: backs the Jobs screen's initial/reconnect list — the
  // broadcast/rebroadcast socket stream alone can't (see
  // MatchingService.listAvailable's own doc comment). Runner-only, same
  // check MatchingService.listAvailable itself enforces.
  @Get('available')
  @UseGuards(JwtAuthGuard)
  listAvailable(@CurrentUser() user: JwtPayload) {
    return this.matching.listAvailable(user);
  }
}
