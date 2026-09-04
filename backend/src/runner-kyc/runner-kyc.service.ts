import { BadRequestException, Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SubmitRunnerKycDto } from './dto/submit-runner-kyc.dto';

@Injectable()
export class RunnerKycService {
  constructor(private readonly prisma: PrismaService) {}

  // Task 29: real submit-for-review. Upserted (not created fresh every
  // time) so a resubmission after rejection reuses the same row/id rather
  // than accumulating history — matches VendorsService.upsertMyVendor's own
  // convention. Always resets to `pending` and clears any prior rejection
  // reason: a resubmission is a fresh review request, not an edit of a
  // still-pending one.
  async submit(userId: string, dto: SubmitRunnerKycDto) {
    const needsVehicle = dto.runnerType === 'independent_rider';
    if (needsVehicle) {
      if (!dto.vehiclePhotoUrl || !dto.vehicleType) {
        throw new BadRequestException('An independent rider must submit a vehicle photo and vehicle type');
      }
      if (dto.vehicleType !== 'bicycle' && !dto.vehiclePlate) {
        throw new BadRequestException('A plate/registration number is required for a motorised vehicle');
      }
    }

    return this.prisma.runnerKyc.upsert({
      where: { userId },
      create: {
        userId,
        runnerType: dto.runnerType,
        idType: dto.idType,
        idPhotoUrl: dto.idPhotoUrl,
        selfiePhotoUrl: dto.selfiePhotoUrl,
        vehiclePhotoUrl: needsVehicle ? dto.vehiclePhotoUrl : null,
        vehicleType: needsVehicle ? dto.vehicleType : null,
        vehiclePlate: needsVehicle ? dto.vehiclePlate : null,
        status: 'pending',
      },
      update: {
        runnerType: dto.runnerType,
        idType: dto.idType,
        idPhotoUrl: dto.idPhotoUrl,
        selfiePhotoUrl: dto.selfiePhotoUrl,
        vehiclePhotoUrl: needsVehicle ? dto.vehiclePhotoUrl : null,
        vehicleType: needsVehicle ? dto.vehicleType : null,
        vehiclePlate: needsVehicle ? dto.vehiclePlate : null,
        status: 'pending',
        rejectionReason: null,
        reviewedAt: null,
      },
    });
  }
}
