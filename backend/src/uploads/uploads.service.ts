import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PresignUploadDto } from './dto/presign-upload.dto';

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const PRESIGN_EXPIRY_SECONDS = 5 * 60;

@Injectable()
export class UploadsService {
  private readonly s3: S3Client;

  constructor(private readonly config: ConfigService) {
    this.s3 = new S3Client({
      region: this.config.get<string>('s3.region'),
      credentials: {
        accessKeyId: this.config.get<string>('s3.accessKeyId') as string,
        secretAccessKey: this.config.get<string>('s3.secretAccessKey') as string,
      },
    });
  }

  async presign(dto: PresignUploadDto) {
    const bucket = this.config.get<string>('s3.bucket');
    const extension = EXTENSION_BY_CONTENT_TYPE[dto.contentType];
    const key = `${dto.purpose}/${randomUUID()}.${extension}`;

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: dto.contentType,
    });
    const uploadUrl = await getSignedUrl(this.s3, command, { expiresIn: PRESIGN_EXPIRY_SECONDS });

    return {
      uploadUrl,
      publicUrl: `${this.config.get<string>('s3.publicBaseUrl')}/${key}`,
      expiresInSeconds: PRESIGN_EXPIRY_SECONDS,
    };
  }
}
