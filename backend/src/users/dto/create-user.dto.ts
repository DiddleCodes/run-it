import { IsEmail, IsIn, IsOptional, IsPhoneNumber, ValidateIf } from 'class-validator';

export class CreateUserDto {
  @ValidateIf((o) => !o.phone)
  @IsEmail()
  email?: string;

  @ValidateIf((o) => !o.email)
  @IsPhoneNumber()
  phone?: string;

  @IsIn(['student', 'runner', 'restaurant'])
  accountType!: 'student' | 'runner' | 'restaurant';
}
