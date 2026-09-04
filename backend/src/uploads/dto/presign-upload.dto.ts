import { IsIn, IsInt, Max, Min } from 'class-validator';

// Task 11: 'delivery-proof' is uploaded by a runner (not a vendor) — see
// UploadsController's doc comment. Task 29: the three 'runner-kyc-*'
// purposes are the real photo uploads behind SubmitRunnerKycDto — same
// presign-then-PUT-then-register flow, just a different registering
// endpoint (POST /runner-kyc/submit instead of the delivery-proof route).
// Task 30: 'handoff-photo' is the runner's required pickup-handoff photo
// (registered via POST /orders/:orderId/verify-pickup); 'dispute-report'
// is the student's optional problem-report photo (registered via POST
// /orders/:orderId/report).
export const UPLOAD_PURPOSES = [
  'menu-item-photo',
  'vendor-logo',
  'delivery-proof',
  'runner-kyc-id',
  'runner-kyc-selfie',
  'runner-kyc-vehicle',
  'handoff-photo',
  'dispute-report',
] as const;
export type UploadPurpose = (typeof UPLOAD_PURPOSES)[number];

const ALLOWED_CONTENT_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;
export type AllowedContentType = (typeof ALLOWED_CONTENT_TYPES)[number];

export class PresignUploadDto {
  @IsIn(ALLOWED_CONTENT_TYPES)
  contentType!: AllowedContentType;

  @IsIn(UPLOAD_PURPOSES)
  purpose!: UploadPurpose;

  // Declared upfront so we can reject an oversized upload before issuing a
  // URL for it. Note this is advisory, not enforced during the actual PUT —
  // a presigned PUT URL (unlike a presigned POST policy) can't carry a
  // content-length condition, so a client could still upload more than it
  // declared. Acceptable here since the uploader is always an
  // authenticated user (vendor or runner), never an anonymous public client.
  @IsInt()
  @Min(1)
  @Max(5 * 1024 * 1024)
  contentLengthBytes!: number;
}
