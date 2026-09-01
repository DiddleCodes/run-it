import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { DevOnlyGuard } from '../common/guards/dev-only.guard';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { SelfOrAdminGuard } from '../common/guards/self-or-admin.guard';
import { CreateUserDto } from './dto/create-user.dto';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  // Task 18: real signups go through AuthService.verifyOtp's own
  // find-or-create — this route's only remaining caller is
  // DemoIdentityService's unauthenticated restaurant/runner identity
  // bridge, the same dev-only stand-in that mints its session via
  // /auth/dev-token. Gated the same way for the same reason: disabled in
  // production, fine for local/staging use.
  @UseGuards(DevOnlyGuard)
  @Post()
  create(@Body() dto: CreateUserDto) {
    return this.users.create(dto);
  }

  @UseGuards(JwtAuthGuard, SelfOrAdminGuard)
  @Get(':userId')
  findOne(@Param('userId') userId: string) {
    return this.users.findById(userId);
  }
}
