import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/kyc_flow_controller.dart' show IdType;
import '../../features/auth/domain/auth_models.dart' show RunnerType, VehicleType;
import 'api_client.dart';

final runnerKycRepositoryProvider = Provider<RunnerKycRepository>(
  (ref) => const RunnerKycRepository(),
);

String _runnerTypeWire(RunnerType type) => switch (type) {
  RunnerType.studentRunner => 'student_runner',
  RunnerType.independentRider => 'independent_rider',
};

String _idTypeWire(IdType type) => switch (type) {
  IdType.studentId => 'student_id',
  IdType.governmentId => 'government_id',
};

// Task 29: the real submit-for-review call — three real S3 URLs (already
// uploaded via UploadsRepository, same presign-then-PUT flow
// DeliveryProofCaptureScreen uses) plus the declarative fields the KYC
// capture wizard collects. Replaces the old client-only
// AuthController.submitKyc()/_resolveKyc() fake resolution for runners —
// see the Task 28 audit report for what that looked like.
class RunnerKycRepository {
  const RunnerKycRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<void> submit({
    required String token,
    required RunnerType runnerType,
    required IdType idType,
    required String idPhotoUrl,
    required String selfiePhotoUrl,
    String? vehiclePhotoUrl,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) async {
    await client.post(
      '/runner-kyc/submit',
      token: token,
      body: {
        'runnerType': _runnerTypeWire(runnerType),
        'idType': _idTypeWire(idType),
        'idPhotoUrl': idPhotoUrl,
        'selfiePhotoUrl': selfiePhotoUrl,
        'vehiclePhotoUrl': ?vehiclePhotoUrl,
        // Prisma's RunnerVehicleType enum values (bicycle/motorbike/keke)
        // match VehicleType.name exactly — no separate wire-mapping needed.
        'vehicleType': ?vehicleType?.name,
        'vehiclePlate': ?vehiclePlate,
      },
    );
  }
}
