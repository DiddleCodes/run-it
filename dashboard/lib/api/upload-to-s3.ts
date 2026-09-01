"use client";

import { vendorClient } from "./vendor-client";

const CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;
type AllowedContentType = (typeof CONTENT_TYPES)[number];

function isAllowedContentType(type: string): type is AllowedContentType {
  return (CONTENT_TYPES as readonly string[]).includes(type);
}

/**
 * Presign (via our proxy) then PUT the raw bytes directly to S3 — the
 * browser talks to S3 itself for this one step, bypassing our backend
 * entirely, exactly as the presigned-URL contract intends (mirrors the
 * mobile app's UploadsRepository.uploadImage).
 */
export async function uploadImageToS3(file: File, purpose: "menu-item-photo" | "vendor-logo"): Promise<string> {
  if (!isAllowedContentType(file.type)) {
    throw new Error("Only JPEG, PNG, or WEBP images are supported.");
  }

  const { uploadUrl, publicUrl } = await vendorClient.presignUpload({
    contentType: file.type,
    purpose,
    contentLengthBytes: file.size,
  });

  const res = await fetch(uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": file.type },
    body: file,
  });

  if (!res.ok) {
    throw new Error(`Upload failed (HTTP ${res.status})`);
  }

  return publicUrl;
}
