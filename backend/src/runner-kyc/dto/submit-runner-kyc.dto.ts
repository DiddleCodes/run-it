import { IsIn, IsOptional, IsString, MinLength } from 'class-validator';
import { RunnerKycIdType, RunnerKycRunnerType, RunnerVehicleType } from '@prisma/client';
import { IsPrivateFileRef } from '../../uploads/private-files';

const RUNNER_TYPES: RunnerKycRunnerType[] = ['student_runner', 'independent_rider'];
const ID_TYPES: RunnerKycIdType[] = ['student_id', 'government_id'];
const VEHICLE_TYPES: RunnerVehicleType[] = ['bicycle', 'motorbike', 'keke'];

// Task 29: the real submit-for-review payload — three private-bucket
// references (`fileUrl` from POST /uploads/presign; RunnerKycService also
// checks they're the runner's own uploads) plus the
// declarative fields the KYC capture wizard collects. `vehiclePhotoUrl`/
// `vehicleType`/`vehiclePlate` are only required for an independent rider
// — RunnerKycService enforces that conditional requirement itself, since
// class-validator has no clean way to express "required if runnerType is
// X" declaratively here.
export class SubmitRunnerKycDto {
  @IsIn(RUNNER_TYPES)
  runnerType!: RunnerKycRunnerType;

  @IsOptional()
  @IsIn(ID_TYPES)
  idType?: RunnerKycIdType;

  @IsPrivateFileRef('runner-kyc-id')
  idPhotoUrl!: string;

  @IsPrivateFileRef('runner-kyc-selfie')
  selfiePhotoUrl!: string;

  @IsOptional()
  @IsPrivateFileRef('runner-kyc-vehicle')
  vehiclePhotoUrl?: string;

  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicleType?: RunnerVehicleType;

  @IsOptional()
  @IsString()
  @MinLength(1)
  vehiclePlate?: string;
}
