import { IsIn, IsInt, Max, Min } from 'class-validator';
import { UPLOAD_PURPOSES, UploadPurpose } from '../private-files';

// Which purpose goes to which bucket is in ../private-files.ts. Registering
// endpoints: menu-item-photo / vendor-logo (restaurant menu and profile),
// runner-kyc-* (POST /runner-kyc/submit), handoff-photo (POST
// /orders/:orderId/verify-pickup), delivery-proof (POST
// /orders/:orderId/delivery-proof), dispute-report (POST
// /orders/:orderId/report).
export { UPLOAD_PURPOSES };
export type { UploadPurpose };

export const MAX_UPLOAD_BYTES = 5 * 1024 * 1024;

const ALLOWED_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export type AllowedContentType = (typeof ALLOWED_CONTENT_TYPES)[number];

export class PresignUploadDto {
  @IsIn(ALLOWED_CONTENT_TYPES)
  contentType!: AllowedContentType;

  @IsIn(UPLOAD_PURPOSES)
  purpose!: UploadPurpose;

  // The exact size of the file about to be uploaded. It's signed into the
  // upload URL (Content-Length), so storage rejects a PUT of any other
  // size — the 5 MB cap holds for the upload itself, not just this request.
  @IsInt()
  @Min(1)
  @Max(MAX_UPLOAD_BYTES)
  contentLengthBytes!: number;
}
