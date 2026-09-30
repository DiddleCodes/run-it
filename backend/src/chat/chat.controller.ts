import { Body, Controller, Get, HttpCode, Param, Post, UseGuards } from '@nestjs/common';
import { JwtPayload } from '../auth/jwt-payload.interface';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { ChatService } from './chat.service';
import { SendMessageDto } from './dto/send-message.dto';

// Task 78: an order's chat. Who may use it (the order's student and its
// assigned runner, never anyone else — not even the restaurant) is enforced
// in ChatService, so it holds for every route here and for the socket.
// orderId is deliberately not UUID-validated: the mobile app mints its own
// ids ("order-<micros>"), and the ChatService lookup is the real check.
@Controller('orders/:orderId/messages')
@UseGuards(JwtAuthGuard)
export class OrderMessagesController {
  constructor(private readonly chat: ChatService) {}

  @Get()
  history(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload) {
    return this.chat.history(orderId, user.sub);
  }

  @Post()
  send(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload, @Body() dto: SendMessageDto) {
    return this.chat.send(orderId, user.sub, dto.body);
  }

  @Post('read')
  @HttpCode(200)
  markRead(@Param('orderId') orderId: string, @CurrentUser() user: JwtPayload) {
    return this.chat.markRead(orderId, user.sub);
  }
}

// Always "my own" threads, scoped by the JWT — same shape as GET /orders.
@Controller('messages')
@UseGuards(JwtAuthGuard)
export class MessageThreadsController {
  constructor(private readonly chat: ChatService) {}

  @Get('threads')
  threads(@CurrentUser() user: JwtPayload) {
    return this.chat.threads(user.sub);
  }
}
