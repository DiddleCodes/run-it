import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { PresignUploadDto } from './dto/presign-upload.dto';
import { UploadsService } from './uploads.service';

@Controller('uploads')
export class UploadsController {
  constructor(private readonly uploads: UploadsService) {}

  // Any authenticated user — a vendor for a menu-item photo/logo, or (Task
  // 11) a runner submitting delivery-proof — the resulting URL only permits
  // a PUT to one freshly generated key, so there's nothing to scope further.
  @Post('presign')
  @UseGuards(JwtAuthGuard)
  presign(@Body() dto: PresignUploadDto) {
    return this.uploads.presign(dto);
  }
}
