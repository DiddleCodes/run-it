"use client";

import { useEffect, useMemo, useRef } from "react";

interface PhotoUploadFieldProps {
  label: string;
  existingUrl: string | null;
  file: File | null;
  onFileChange: (file: File | null) => void;
}

/**
 * Holds the picked file locally for preview only — the actual presign +
 * direct-S3-PUT upload happens when the parent form is saved, mirroring the
 * mobile app's menu-item photo flow (pick now, upload at Save, not on pick).
 */
export function PhotoUploadField({ label, existingUrl, file, onFileChange }: PhotoUploadFieldProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  // Derived, not state — createObjectURL is cheap and synchronous, so the
  // preview URL can be computed directly during render; the effect below
  // only handles cleanup (revoking), never setState.
  const previewUrl = useMemo(() => (file ? URL.createObjectURL(file) : null), [file]);

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  const displayUrl = previewUrl ?? existingUrl;

  return (
    <div>
      <label className="block text-xs font-medium text-[var(--muted-foreground)] mb-1.5">{label}</label>
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        className="hidden"
        onChange={(e) => onFileChange(e.target.files?.[0] ?? null)}
      />
      <div className="border-2 border-dashed border-[var(--border)] rounded-lg p-4 text-center bg-[var(--secondary)]">
        {displayUrl ? (
          <div className="flex items-center gap-3">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={displayUrl} alt="" className="w-14 h-14 rounded-lg object-cover flex-shrink-0" />
            <div className="text-left">
              <p className="text-xs font-medium text-[var(--foreground)]">{file ? "New photo selected" : "Photo attached"}</p>
              <div className="flex gap-3 mt-0.5">
                <button type="button" onClick={() => inputRef.current?.click()} className="text-xs text-[var(--primary)]">
                  Replace
                </button>
                <button
                  type="button"
                  onClick={() => {
                    onFileChange(null);
                    if (inputRef.current) inputRef.current.value = "";
                  }}
                  className="text-xs text-red-500"
                >
                  Remove
                </button>
              </div>
            </div>
          </div>
        ) : (
          <button type="button" onClick={() => inputRef.current?.click()} className="w-full">
            <svg className="mx-auto mb-2 text-[var(--muted-foreground)]" width="24" height="24" viewBox="0 0 24 24" fill="none">
              <path d="M21 19V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2h14a2 2 0 002-2z" stroke="currentColor" strokeWidth="1.5" />
              <circle cx="8" cy="10" r="1.5" stroke="currentColor" strokeWidth="1.5" />
              <path d="M21 15l-5-5-9 9" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
            </svg>
            <p className="text-xs text-[var(--muted-foreground)]">Click to upload</p>
            <p className="text-[10px] text-[var(--muted-foreground)] mt-0.5">JPEG, PNG or WEBP, up to 5MB</p>
          </button>
        )}
      </div>
    </div>
  );
}
