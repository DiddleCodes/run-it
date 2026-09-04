import { IsNotEmpty, IsString } from 'class-validator';

export class CheckEmailQueryDto {
  @IsString()
  @IsNotEmpty()
  email!: string;
}
