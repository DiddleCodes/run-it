import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { ESCALATE_JOB, MATCHING_QUEUE, REBROADCAST_JOB } from './matching.constants';
import { MatchingService } from './matching.service';

export interface MatchingJobData {
  orderId: string;
}

@Processor(MATCHING_QUEUE)
export class MatchingProcessor extends WorkerHost {
  private readonly logger = new Logger(MatchingProcessor.name);

  constructor(private readonly matching: MatchingService) {
    super();
  }

  async process(job: Job<MatchingJobData>): Promise<void> {
    switch (job.name) {
      case REBROADCAST_JOB:
        return this.matching.handleRebroadcast(job.data.orderId);
      case ESCALATE_JOB:
        return this.matching.handleEscalate(job.data.orderId);
      default:
        this.logger.warn(`Unknown matching job name: ${job.name}`);
    }
  }
}
