import { IsIn, IsOptional, IsString, MinLength } from 'class-validator';

export const DEVICE_PLATFORMS = ['ios', 'android', 'web'] as const;
export type DevicePlatform = (typeof DEVICE_PLATFORMS)[number];

export class RegisterDeviceTokenDto {
  @IsString()
  @MinLength(10)
  token!: string;

  @IsOptional()
  @IsIn(DEVICE_PLATFORMS)
  platform?: DevicePlatform;
}
