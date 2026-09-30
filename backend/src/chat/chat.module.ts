import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { MessageThreadsController, OrderMessagesController } from './chat.controller';
import { ChatGateway } from './chat.gateway';
import { ChatService } from './chat.service';

@Module({
  // CommonModule: JwtAuthGuard for the controllers and (via AuthModule)
  // JwtService for the gateway's handshake. NotificationsModule: the
  // emitter "new message" pushes go through.
  imports: [CommonModule, NotificationsModule],
  controllers: [OrderMessagesController, MessageThreadsController],
  providers: [ChatService, ChatGateway],
})
export class ChatModule {}
