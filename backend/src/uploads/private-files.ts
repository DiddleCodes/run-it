import { BadRequestException } from '@nestjs/common';
import { Matches } from 'class-validator';

/**
 * Two buckets. Menu photos and restaurant logos are shown to everyone, so
 * they live in the public bucket (S3_UPLOADS_BUCKET) and are stored as
 * plain public URLs. Everything below is personal or evidential — ID
 * cards, selfies, delivery and dispute photos — and lives in the private
 * bucket (S3_PRIVATE_BUCKET): it is stored as a `private://` reference, is
 * never readable by URL, and is only ever shown through a short-lived
 * signed read URL handed to someone allowed to see it (UploadsService
 * .signedReadUrl, called only from admin-only endpoints today).
 */
export const PUBLIC_UPLOAD_PURPOSES = ['menu-item-photo', 'vendor-logo'] as const;
export const PRIVATE_UPLOAD_PURPOSES = [
  'runner-kyc-id',
  'runner-kyc-selfie',
  'runner-kyc-vehicle',
  'delivery-proof',
  'handoff-photo',
  'dispute-report',
] as const;
export const UPLOAD_PURPOSES = [...PUBLIC_UPLOAD_PURPOSES, ...PRIVATE_UPLOAD_PURPOSES] as const;

export type PublicUploadPurpose = (typeof PUBLIC_UPLOAD_PURPOSES)[number];
export type PrivateUploadPurpose = (typeof PRIVATE_UPLOAD_PURPOSES)[number];
export type UploadPurpose = (typeof UPLOAD_PURPOSES)[number];

export function isPrivatePurpose(purpose: string): purpose is PrivateUploadPurpose {
  return (PRIVATE_UPLOAD_PURPOSES as readonly string[]).includes(purpose);
}

const PRIVATE_SCHEME = 'private://';

/** `private://<purpose>/<uploader user id>/<uuid>.<ext>` — the object key, behind a scheme no browser can load. */
export function privateFileRef(key: string): string {
  return `${PRIVATE_SCHEME}${key}`;
}

const REF_PATTERN = (purpose: string) =>
  new RegExp(`^private://${purpose}/[A-Za-z0-9_-]{1,64}/[0-9a-f-]{36}\\.(jpg|png|webp)$`);

export interface PrivateFile {
  purpose: PrivateUploadPurpose;
  ownerId: string;
  key: string;
}

export function parsePrivateFileRef(value: string | null | undefined): PrivateFile | null {
  if (!value?.startsWith(PRIVATE_SCHEME)) return null;
  const key = value.slice(PRIVATE_SCHEME.length);
  const [purpose, ownerId] = key.split('/');
  if (!isPrivatePurpose(purpose) || !REF_PATTERN(purpose).test(value)) return null;
  return { purpose, ownerId, key };
}

/** DTO check: the value must be a private upload of this purpose (not any URL). */
export function IsPrivateFileRef(purpose: PrivateUploadPurpose) {
  return Matches(REF_PATTERN(purpose), {
    message: `$property must be a ${purpose} upload from POST /uploads/presign`,
  });
}

/**
 * Service check, once the caller is known: the file must be one the caller
 * uploaded themselves — so nobody can attach someone else's ID photo or
 * evidence by reusing a reference they've seen.
 */
export function requireOwnPrivateFile(value: string, purpose: PrivateUploadPurpose, userId: string): string {
  const file = parsePrivateFileRef(value);
  if (!file || file.purpose !== purpose) {
    throw new BadRequestException(`Expected a ${purpose} upload from POST /uploads/presign`);
  }
  if (file.ownerId !== userId) {
    throw new BadRequestException('That photo was uploaded by someone else — upload your own');
  }
  return value;
}
