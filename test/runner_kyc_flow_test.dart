import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/kyc_flow_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';

/// A tiny non-empty byte payload — only `vehiclePhoto != null` is ever
/// checked by [KycCapture.hasVehiclePhoto], so the actual bytes are
/// irrelevant.
final _stubPhotoBytes = Uint8List.fromList(const [1]);

AuthSession _session({required KycStatus kycStatus}) => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: 'runner-1',
    name: 'Test Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: kycStatus,
  ),
);

void main() {
  group('kycStepsFor branches by runner type', () {
    test('student runner: no vehicle steps', () {
      final steps = kycStepsFor(
        true,
        const KycCapture(runnerType: RunnerType.studentRunner),
      );
      expect(steps, [
        KycStepKind.id,
        KycStepKind.selfie,
        KycStepKind.almostThere,
      ]);
      expect(steps, isNot(contains(KycStepKind.vehiclePhoto)));
      expect(steps, isNot(contains(KycStepKind.vehicleDetails)));
    });

    test(
      'independent rider: vehicle photo + details inserted after selfie',
      () {
        final steps = kycStepsFor(
          true,
          const KycCapture(runnerType: RunnerType.independentRider),
        );
        expect(steps, [
          KycStepKind.id,
          KycStepKind.selfie,
          KycStepKind.vehiclePhoto,
          KycStepKind.vehicleDetails,
          KycStepKind.almostThere,
        ]);
      },
    );

    test(
      'light KYC (student account) is unaffected by runner-type branching',
      () {
        final steps = kycStepsFor(
          false,
          const KycCapture(runnerType: RunnerType.independentRider),
        );
        expect(steps, [
          KycStepKind.id,
          KycStepKind.studentDetails,
          KycStepKind.almostThere,
        ]);
      },
    );
  });

  group('vehicle field validation', () {
    test('bicycle: plate is optional', () {
      const capture = KycCapture(vehicleType: VehicleType.bicycle);
      expect(capture.plateRequired, isFalse);
      expect(capture.plateValid, isTrue);
    });

    test('motorbike/keke: plate is required and validated', () {
      const withoutPlate = KycCapture(vehicleType: VehicleType.motorbike);
      expect(withoutPlate.plateRequired, isTrue);
      expect(withoutPlate.plateValid, isFalse);

      const blankPlate = KycCapture(
        vehicleType: VehicleType.keke,
        plateNumber: '   ',
      );
      expect(blankPlate.plateValid, isFalse);

      const withPlate = KycCapture(
        vehicleType: VehicleType.motorbike,
        plateNumber: 'ABC-123-XY',
      );
      expect(withPlate.plateValid, isTrue);
    });

    test('vehicleStepComplete requires photo + type + a valid plate', () {
      const empty = KycCapture(runnerType: RunnerType.independentRider);
      expect(empty.needsVehicleStep, isTrue);
      expect(empty.vehicleStepComplete, isFalse);

      final photoOnly = empty.copyWith(vehiclePhoto: _stubPhotoBytes);
      expect(photoOnly.vehicleStepComplete, isFalse);

      final bicycleDone = photoOnly.copyWith(vehicleType: VehicleType.bicycle);
      expect(bicycleDone.vehicleStepComplete, isTrue);

      final motorbikeNoPlate = photoOnly.copyWith(
        vehicleType: VehicleType.motorbike,
      );
      expect(motorbikeNoPlate.vehicleStepComplete, isFalse);

      final motorbikeWithPlate = motorbikeNoPlate.copyWith(
        plateNumber: 'XY-99-ZZ',
      );
      expect(motorbikeWithPlate.vehicleStepComplete, isTrue);

      // A student runner never needs the vehicle step, regardless of state.
      const studentRunner = KycCapture(runnerType: RunnerType.studentRunner);
      expect(studentRunner.needsVehicleStep, isFalse);
      expect(studentRunner.vehicleStepComplete, isTrue);
    });
  });

  group('postAuthDestination for returning runners', () {
    // TASK 4g §1: a non-Verified runner keeps limited app access (browse
    // Jobs read-only, a Pending-review Profile state) rather than being
    // parked on a standalone status screen — so every returning runner,
    // Verified or not, lands in the runner shell. The shell itself
    // degrades for a non-Verified runner; it's no longer a blocked screen.
    test('a runner mid-review (pending) lands on the runner home shell', () {
      final destination = postAuthDestination(
        _session(kycStatus: KycStatus.pending).user,
      );
      expect(destination, AppRoutes.runnerHome);
    });

    test('a rejected runner also lands on the runner home shell', () {
      expect(
        postAuthDestination(_session(kycStatus: KycStatus.rejected).user),
        AppRoutes.runnerHome,
      );
    });

    test('a verified runner returns straight to the runner home', () {
      expect(
        postAuthDestination(_session(kycStatus: KycStatus.verified).user),
        AppRoutes.runnerHome,
      );
    });
  });

  group('isPlausiblePlateNumber — lenient format validation', () {
    test('accepts informal/hand-painted-style plates', () {
      expect(isPlausiblePlateNumber('ABC-123-XY'), isTrue);
      expect(isPlausiblePlateNumber('KJA234XY'), isTrue);
      // Short, all-numeric, or lowercase informal plates should still pass
      // — the rule is "not obvious junk", not "matches one exact pattern".
      expect(isPlausiblePlateNumber('kk123'), isTrue);
      expect(isPlausiblePlateNumber('12A'), isTrue);
    });

    test('rejects obvious junk', () {
      expect(isPlausiblePlateNumber(''), isFalse);
      expect(isPlausiblePlateNumber('  '), isFalse);
      expect(isPlausiblePlateNumber('A'), isFalse); // single character
      expect(isPlausiblePlateNumber('000000'), isFalse); // all zeros
      expect(isPlausiblePlateNumber('AAAA'), isFalse); // all one letter
      expect(isPlausiblePlateNumber('##%%##'), isFalse); // not alphanumeric
      expect(
        isPlausiblePlateNumber('THIS-IS-WAY-TOO-LONG-1234'),
        isFalse,
      ); // unreasonably long
    });
  });
}
