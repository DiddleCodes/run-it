import { IsPrivateFileRef } from '../../uploads/private-files';

export class DeliveryProofDto {
  // The `fileUrl` (a private-bucket reference) returned by POST
  // /uploads/presign, once the runner has PUT the photo — this endpoint
  // never accepts the raw image itself. Must be the runner's own upload.
  @IsPrivateFileRef('delivery-proof')
  photoUrl!: string;
}
