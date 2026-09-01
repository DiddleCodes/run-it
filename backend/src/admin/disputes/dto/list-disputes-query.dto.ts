import { IsIn, IsOptional } from 'class-validator';
import { DisputeStatus } from '@prisma/client';

const DISPUTE_STATUSES: DisputeStatus[] = ['open', 'resolved'];

export class ListDisputesQueryDto {
  @IsOptional()
  @IsIn(DISPUTE_STATUSES)
  status?: DisputeStatus;
}
