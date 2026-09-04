import { Module } from '@nestjs/common';
import { CommonModule } from '../common/common.module';
import { RunnerKycController } from './runner-kyc.controller';
import { RunnerKycService } from './runner-kyc.service';

@Module({
  imports: [CommonModule],
  controllers: [RunnerKycController],
  providers: [RunnerKycService],
})
export class RunnerKycModule {}
