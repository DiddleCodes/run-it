import { IsUrl } from 'class-validator';

export class DeliveryProofDto {
  // The `publicUrl` returned by POST /uploads/presign, once the runner has
  // actually PUT the photo to that URL — this endpoint never accepts the
  // raw image itself, same upload-then-register pattern as menu-item photos.
  @IsUrl()
  photoUrl!: string;
}
