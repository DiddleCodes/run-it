import { IsIn, IsOptional, IsString, MinLength } from 'class-validator';
import { RunnerKycIdType, RunnerKycRunnerType, RunnerVehicleType } from '@prisma/client';

const RUNNER_TYPES: RunnerKycRunnerType[] = ['student_runner', 'independent_rider'];
const ID_TYPES: RunnerKycIdType[] = ['student_id', 'government_id'];
const VEHICLE_TYPES: RunnerVehicleType[] = ['bicycle', 'motorbike', 'keke'];

// Task 29: the real submit-for-review payload — three real S3 URLs (from
// POST /uploads/presign, same pattern as delivery-proof) plus the
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

  @IsString()
  @MinLength(1)
  idPhotoUrl!: string;

  @IsString()
  @MinLength(1)
  selfiePhotoUrl!: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  vehiclePhotoUrl?: string;

  @IsOptional()
  @IsIn(VEHICLE_TYPES)
  vehicleType?: RunnerVehicleType;

  @IsOptional()
  @IsString()
  @MinLength(1)
  vehiclePlate?: string;
}
