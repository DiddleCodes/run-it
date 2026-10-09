import { BadRequestException } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { DeliveryProofDto } from '../src/orders/dto/delivery-proof.dto';
import { ReportProblemDto } from '../src/orders/dto/report-problem.dto';
import { VerifyPickupDto } from '../src/orders/dto/verify-pickup.dto';
import { SubmitRunnerKycDto } from '../src/runner-kyc/dto/submit-runner-kyc.dto';
import {
  isPrivatePurpose,
  parsePrivateFileRef,
  PRIVATE_UPLOAD_PURPOSES,
  PUBLIC_UPLOAD_PURPOSES,
  requireOwnPrivateFile,
} from '../src/uploads/private-files';

const UUID = '3f2b8c1e-9a4d-4e5f-8b6a-1c2d3e4f5a6b';
const ref = (purpose: string, owner = 'user-1') => `private://${purpose}/${owner}/${UUID}.jpg`;

describe('private files', () => {
  it('splits purposes into exactly the two buckets', () => {
    expect([...PUBLIC_UPLOAD_PURPOSES]).toEqual(['menu-item-photo', 'vendor-logo']);
    expect([...PRIVATE_UPLOAD_PURPOSES].sort()).toEqual(
      ['delivery-proof', 'dispute-report', 'handoff-photo', 'runner-kyc-id', 'runner-kyc-selfie', 'runner-kyc-vehicle'].sort(),
    );
    expect(isPrivatePurpose('menu-item-photo')).toBe(false);
    expect(isPrivatePurpose('runner-kyc-id')).toBe(true);
  });

  it('parses a reference, and rejects anything else', () => {
    expect(parsePrivateFileRef(ref('delivery-proof', 'runner-9'))).toEqual({
      purpose: 'delivery-proof',
      ownerId: 'runner-9',
      key: `delivery-proof/runner-9/${UUID}.jpg`,
    });
    for (const bad of [
      null,
      '',
      'https://cdn.example.com/x.jpg',
      ref('menu-item-photo'),
      `private://delivery-proof/runner-9/${UUID}.gif`,
      `private://delivery-proof/../runner-9/${UUID}.jpg`,
      `private://delivery-proof/runner-9/x/${UUID}.jpg`,
    ]) {
      expect(parsePrivateFileRef(bad)).toBeNull();
    }
  });

  it("only the uploader's own photo of the right kind is accepted", () => {
    expect(requireOwnPrivateFile(ref('handoff-photo', 'runner-1'), 'handoff-photo', 'runner-1')).toBe(
      ref('handoff-photo', 'runner-1'),
    );
    expect(() => requireOwnPrivateFile(ref('handoff-photo', 'runner-2'), 'handoff-photo', 'runner-1')).toThrow(
      /uploaded by someone else/,
    );
    expect(() => requireOwnPrivateFile(ref('delivery-proof', 'runner-1'), 'handoff-photo', 'runner-1')).toThrow(
      BadRequestException,
    );
    expect(() => requireOwnPrivateFile('https://cdn.example.com/x.jpg', 'handoff-photo', 'runner-1')).toThrow(
      BadRequestException,
    );
  });

  describe('the registering endpoints accept only a private reference of their own kind', () => {
    const errorsFor = async (cls: any, body: object) =>
      (await validate(plainToInstance(cls, body) as object)).map((e) => e.property);

    it('verify-pickup', async () => {
      expect(await errorsFor(VerifyPickupDto, { code: '1234', handoffPhotoUrl: ref('handoff-photo') })).toEqual([]);
      expect(await errorsFor(VerifyPickupDto, { code: '1234', handoffPhotoUrl: 'https://cdn.example.com/x.jpg' })).toEqual([
        'handoffPhotoUrl',
      ]);
      expect(await errorsFor(VerifyPickupDto, { code: '1234', handoffPhotoUrl: ref('delivery-proof') })).toEqual([
        'handoffPhotoUrl',
      ]);
    });

    it('delivery-proof', async () => {
      expect(await errorsFor(DeliveryProofDto, { photoUrl: ref('delivery-proof') })).toEqual([]);
      expect(await errorsFor(DeliveryProofDto, { photoUrl: 'https://cdn.example.com/x.jpg' })).toEqual(['photoUrl']);
    });

    it('report a problem (photo optional)', async () => {
      expect(await errorsFor(ReportProblemDto, { reason: 'Cold food' })).toEqual([]);
      expect(await errorsFor(ReportProblemDto, { reason: 'Cold food', photoUrl: ref('dispute-report') })).toEqual([]);
      expect(await errorsFor(ReportProblemDto, { reason: 'Cold food', photoUrl: 'https://x.co/a.jpg' })).toEqual(['photoUrl']);
    });

    it('runner verification', async () => {
      const good = {
        runnerType: 'independent_rider',
        idPhotoUrl: ref('runner-kyc-id'),
        selfiePhotoUrl: ref('runner-kyc-selfie'),
        vehiclePhotoUrl: ref('runner-kyc-vehicle'),
        vehicleType: 'bicycle',
      };
      expect(await errorsFor(SubmitRunnerKycDto, good)).toEqual([]);
      expect(
        await errorsFor(SubmitRunnerKycDto, { ...good, idPhotoUrl: ref('runner-kyc-selfie'), selfiePhotoUrl: 'selfie.jpg' }),
      ).toEqual(['idPhotoUrl', 'selfiePhotoUrl']);
    });
  });
});
