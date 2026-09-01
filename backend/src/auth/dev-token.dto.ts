import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { AppRole } from './jwt-payload.interface';

export class DevTokenDto {
  @IsUUID()
  userId!: string;

  @IsOptional()
  @IsIn(['student', 'runner', 'restaurant', 'admin'])
  accountType?: 'student' | 'runner' | 'restaurant' | 'admin';

  @IsOptional()
  @IsIn(['user', 'admin', 'internal_service'])
  role?: AppRole;
}
