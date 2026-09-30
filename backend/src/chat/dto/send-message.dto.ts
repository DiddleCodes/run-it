import { IsString, MaxLength } from 'class-validator';
import { MAX_MESSAGE_LENGTH } from '../chat.service';

export class SendMessageDto {
  @IsString()
  @MaxLength(MAX_MESSAGE_LENGTH)
  body!: string;
}
