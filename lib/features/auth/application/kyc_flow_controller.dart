import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_models.dart'
    show RunnerType, VehicleType, isPlausiblePlateNumber;

export '../domain/auth_models.dart' show RunnerType, VehicleType;

/// Accepted ID type for the runner ID-capture step — only relevant for a
/// student runner, who may use either; an independent rider is always
/// [governmentId].
enum IdType { studentId, governmentId }

/// Transient wizard state for the KYC capture steps. Separate from
/// [AuthController]'s persisted `kycStatus` — this only exists while the
/// user is actively working through the capture flow, and is discarded
/// once `submitKyc()` hands the result over.
///
/// Captured frames are kept as raw bytes (not a file path) so the same
/// code works on web, where there is no filesystem to point a path at.
class KycCapture {
  const KycCapture({
    this.idImage,
    this.idType = IdType.studentId,
    this.selfieImage,
    this.runnerType,
    this.vehiclePhoto,
    this.vehicleType,
    this.plateNumber,
  });

  final Uint8List? idImage;
  final IdType idType;
  final Uint8List? selfieImage;
  final RunnerType? runnerType;
  final Uint8List? vehiclePhoto;
  final VehicleType? vehicleType;
  final String? plateNumber;

  bool get hasId => idImage != null;
  bool get hasSelfie => selfieImage != null;

  /// Only an independent rider needs the vehicle step at all — a student
  /// runner delivers on foot/between classes, no vehicle to register.
  bool get needsVehicleStep => runnerType == RunnerType.independentRider;

  bool get hasVehiclePhoto => vehiclePhoto != null;

  /// A bicycle has no plate to register; any motorised vehicle does.
  bool get plateRequired =>
      vehicleType != null && vehicleType != VehicleType.bicycle;

  bool get plateValid =>
      !plateRequired || isPlausiblePlateNumber(plateNumber ?? '');

  bool get vehicleStepComplete =>
      !needsVehicleStep ||
      (hasVehiclePhoto && vehicleType != null && plateValid);

  KycCapture copyWith({
    Uint8List? idImage,
    IdType? idType,
    Uint8List? selfieImage,
    RunnerType? runnerType,
    Uint8List? vehiclePhoto,
    VehicleType? vehicleType,
    String? plateNumber,
  }) => KycCapture(
    idImage: idImage ?? this.idImage,
    idType: idType ?? this.idType,
    selfieImage: selfieImage ?? this.selfieImage,
    runnerType: runnerType ?? this.runnerType,
    vehiclePhoto: vehiclePhoto ?? this.vehiclePhoto,
    vehicleType: vehicleType ?? this.vehicleType,
    plateNumber: plateNumber ?? this.plateNumber,
  );
}

class KycFlowController extends Notifier<KycCapture> {
  @override
  KycCapture build() => const KycCapture();

  void setId(Uint8List bytes, {IdType? idType}) =>
      state = state.copyWith(idImage: bytes, idType: idType);
  void setSelfie(Uint8List bytes) => state = state.copyWith(selfieImage: bytes);
  void setRunnerType(RunnerType type) =>
      state = state.copyWith(runnerType: type);
  void setVehiclePhoto(Uint8List bytes) =>
      state = state.copyWith(vehiclePhoto: bytes);
  void setVehicleType(VehicleType type) =>
      state = state.copyWith(vehicleType: type);
  void setPlateNumber(String value) =>
      state = state.copyWith(plateNumber: value);
  void reset() => state = const KycCapture();
}

final kycFlowProvider = NotifierProvider<KycFlowController, KycCapture>(
  KycFlowController.new,
);

/// The ordered steps a given capture session walks through. Light KYC
/// (students) is a fixed 3-step sequence; runner KYC varies by
/// [RunnerType] — a student runner skips the vehicle steps entirely, an
/// independent rider adds them after the selfie. Kept alongside the model
/// it branches on (rather than private to the screen) so the branching
/// itself — which runner type gets which steps — is directly testable.
enum KycStepKind {
  id,
  selfie,
  studentDetails,
  vehiclePhoto,
  vehicleDetails,
  almostThere,
}

List<KycStepKind> kycStepsFor(bool isRunner, KycCapture capture) {
  if (!isRunner) {
    return const [
      KycStepKind.id,
      KycStepKind.studentDetails,
      KycStepKind.almostThere,
    ];
  }
  return [
    KycStepKind.id,
    KycStepKind.selfie,
    if (capture.needsVehicleStep) ...[
      KycStepKind.vehiclePhoto,
      KycStepKind.vehicleDetails,
    ],
    KycStepKind.almostThere,
  ];
}
