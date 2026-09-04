import { BadRequestException } from '@nestjs/common';
import { RunnerKycService } from '../src/runner-kyc/runner-kyc.service';
import { createPrismaMock } from './support/mocks';

function makeService() {
  const prisma = createPrismaMock();
  const service = new RunnerKycService(prisma as any);
  return { service, prisma };
}

const baseDto = {
  runnerType: 'student_runner' as const,
  idType: 'student_id' as const,
  idPhotoUrl: 'https://cdn.example.com/kyc/id.jpg',
  selfiePhotoUrl: 'https://cdn.example.com/kyc/selfie.jpg',
};

describe('RunnerKycService.submit', () => {
  it('upserts a student-runner submission with no vehicle fields, status pending', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.upsert.mockResolvedValue({ id: 'kyc-1', status: 'pending' });

    await service.submit('runner-1', baseDto);

    expect(prisma.runnerKyc.upsert).toHaveBeenCalledWith({
      where: { userId: 'runner-1' },
      create: {
        userId: 'runner-1',
        runnerType: 'student_runner',
        idType: 'student_id',
        idPhotoUrl: baseDto.idPhotoUrl,
        selfiePhotoUrl: baseDto.selfiePhotoUrl,
        vehiclePhotoUrl: null,
        vehicleType: null,
        vehiclePlate: null,
        status: 'pending',
      },
      update: expect.objectContaining({ status: 'pending', rejectionReason: null, reviewedAt: null }),
    });
  });

  it('rejects an independent rider submission missing the vehicle photo/type', async () => {
    const { service } = makeService();

    await expect(
      service.submit('runner-1', { ...baseDto, runnerType: 'independent_rider' }),
    ).rejects.toThrow(BadRequestException);
  });

  it('rejects a motorised independent-rider submission with no plate', async () => {
    const { service } = makeService();

    await expect(
      service.submit('runner-1', {
        ...baseDto,
        runnerType: 'independent_rider',
        vehiclePhotoUrl: 'https://cdn.example.com/kyc/vehicle.jpg',
        vehicleType: 'motorbike',
      }),
    ).rejects.toThrow(BadRequestException);
  });

  it('accepts a bicycle independent-rider submission with no plate', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.upsert.mockResolvedValue({ id: 'kyc-1', status: 'pending' });

    await service.submit('runner-1', {
      ...baseDto,
      runnerType: 'independent_rider',
      vehiclePhotoUrl: 'https://cdn.example.com/kyc/vehicle.jpg',
      vehicleType: 'bicycle',
    });

    const call = prisma.runnerKyc.upsert.mock.calls[0][0];
    expect(call.create.vehicleType).toBe('bicycle');
    // A bicycle has no plate to register — `undefined` (never supplied by
    // the DTO) and `null` (explicitly cleared) both mean "no plate stored"
    // to Prisma, so either is a correct outcome here.
    expect(call.create.vehiclePlate ?? null).toBeNull();
  });

  it('accepts a full independent-rider submission with a plate, and persists it', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.upsert.mockResolvedValue({ id: 'kyc-1', status: 'pending' });

    await service.submit('runner-1', {
      ...baseDto,
      runnerType: 'independent_rider',
      vehiclePhotoUrl: 'https://cdn.example.com/kyc/vehicle.jpg',
      vehicleType: 'motorbike',
      vehiclePlate: 'ABC-123-XY',
    });

    expect(prisma.runnerKyc.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({ vehicleType: 'motorbike', vehiclePlate: 'ABC-123-XY' }),
      }),
    );
  });

  it('a resubmission resets status to pending and clears any prior rejection', async () => {
    const { service, prisma } = makeService();
    prisma.runnerKyc.upsert.mockResolvedValue({ id: 'kyc-1', status: 'pending' });

    await service.submit('runner-1', baseDto);

    const call = prisma.runnerKyc.upsert.mock.calls[0][0];
    expect(call.update.status).toBe('pending');
    expect(call.update.rejectionReason).toBeNull();
    expect(call.update.reviewedAt).toBeNull();
  });
});
