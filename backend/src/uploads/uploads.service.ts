import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'crypto';
import { PresignUploadDto } from './dto/presign-upload.dto';
import { isPrivatePurpose, parsePrivateFileRef, privateFileRef } from './private-files';

const EXTENSION_BY_CONTENT_TYPE: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
};

const PRESIGN_EXPIRY_SECONDS = 5 * 60;
/** How long a signed link to a private photo works. */
export const PRIVATE_READ_EXPIRY_SECONDS = 10 * 60;

/**
 * Provider-neutral: AWS S3 by default; Backblaze B2, Cloudflare R2 or any
 * S3-compatible store by setting S3_ENDPOINT (path-style addressing is
 * used whenever an endpoint is set). Nothing here is provider-specific.
 */
export function createS3Client(config: ConfigService): S3Client {
  const endpoint = config.get<string>('s3.endpoint');
  return new S3Client({
    region: config.get<string>('s3.region'),
    ...(endpoint ? { endpoint, forcePathStyle: true } : {}),
    // The SDK otherwise adds a CRC32 of an *empty* body to every presigned
    // PUT, which makes storage reject every real upload (and B2/R2 don't
    // accept those checksum parameters at all).
    requestChecksumCalculation: 'WHEN_REQUIRED',
    responseChecksumValidation: 'WHEN_REQUIRED',
    credentials: {
      accessKeyId: config.get<string>('s3.accessKeyId') as string,
      secretAccessKey: config.get<string>('s3.secretAccessKey') as string,
    },
  });
}

export interface PresignResult {
  uploadUrl: string;
  /** What to register with the API: a public URL, or a `private://` reference. */
  fileUrl: string;
  /** Only for public purposes — a private photo never has one. */
  publicUrl: string | null;
  expiresInSeconds: number;
}

@Injectable()
export class UploadsService {
  private readonly s3: S3Client;

  constructor(private readonly config: ConfigService) {
    this.s3 = createS3Client(config);
  }

  async presign(dto: PresignUploadDto, uploaderId: string): Promise<PresignResult> {
    const extension = EXTENSION_BY_CONTENT_TYPE[dto.contentType];
    const isPrivate = isPrivatePurpose(dto.purpose);
    // Private keys carry the uploader's id, so a registering endpoint can
    // check the photo is the caller's own (requireOwnPrivateFile).
    const key = isPrivate
      ? `${dto.purpose}/${uploaderId}/${randomUUID()}.${extension}`
      : `${dto.purpose}/${randomUUID()}.${extension}`;

    const command = new PutObjectCommand({
      Bucket: this.config.get<string>(isPrivate ? 's3.privateBucket' : 's3.bucket'),
      Key: key,
      ContentType: dto.contentType,
      // Signed into the URL: storage refuses a body of any other size.
      ContentLength: dto.contentLengthBytes,
    });
    const uploadUrl = await getSignedUrl(this.s3, command, {
      expiresIn: PRESIGN_EXPIRY_SECONDS,
      signableHeaders: new Set(['content-length', 'content-type']),
    });

    const publicUrl = isPrivate ? null : `${this.config.get<string>('s3.publicBaseUrl')}/${key}`;
    return {
      uploadUrl,
      fileUrl: publicUrl ?? privateFileRef(key),
      publicUrl,
      expiresInSeconds: PRESIGN_EXPIRY_SECONDS,
    };
  }

  /**
   * A short-lived link to a private photo. Callers must already have
   * checked the viewer may see it. Anything that isn't a valid private
   * reference (empty, or an old plain URL) gives null — never passed through.
   */
  async signedReadUrl(ref: string | null | undefined): Promise<string | null> {
    const file = parsePrivateFileRef(ref);
    if (!file) return null;
    const command = new GetObjectCommand({ Bucket: this.config.get<string>('s3.privateBucket'), Key: file.key });
    return getSignedUrl(this.s3, command, { expiresIn: PRIVATE_READ_EXPIRY_SECONDS });
  }
}
