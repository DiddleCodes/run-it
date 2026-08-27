import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

const _biometricUserKey = 'runit_biometric_user_v1';
const _passcodeHashKey = 'runit_passcode_hash_v1';
const _passcodeUserKey = 'runit_passcode_user_v1';
// A fixed pepper, not a per-user salt — this is a demo-only local secret
// store (device-bound via FlutterSecureStorage), not a multi-user server
// database where salting defends against a leaked hash table.
const _passcodeSalt = 'runit_passcode_pepper_v1';

class AuthController extends Notifier<AuthSession?> {
  final _repository = const AuthRepository();
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();
  final _random = Random();
  Timer? _refreshTimer;
  Timer? _kycTimer;

  @override
  AuthSession? build() {
    ref.onDispose(() {
      _refreshTimer?.cancel();
      _kycTimer?.cancel();
    });
    return null;
  }

  Future<void> sendOtp(String contact) => _repository.sendOtp(contact);

  Future<bool> verifyOtpAndLogin({
    required String contact,
    required String code,
    required String name,
    required AccountType accountType,
    required String campusId,
    String? classOrGrade,
  }) async {
    final ok = await _repository.verifyOtp(contact, code);
    if (!ok) return false;
    final user = await _repository.register(
      name: name,
      contact: contact,
      accountType: accountType,
      campusId: campusId,
      classOrGrade: classOrGrade,
    );
    state = await _repository.issueSession(user);
    _scheduleSilentRefresh();
    return true;
  }

  void _scheduleSilentRefresh() {
    _refreshTimer?.cancel();
    final session = state;
    if (session == null) return;
    final lead =
        session.expiresAt.difference(DateTime.now()) -
        const Duration(seconds: 6);
    _refreshTimer = Timer(
      lead.isNegative ? Duration.zero : lead,
      _silentRefresh,
    );
  }

  Future<void> _silentRefresh() async {
    final session = state;
    if (session == null) return;
    try {
      state = await _repository.refresh(session);
      _scheduleSilentRefresh();
    } catch (_) {
      logout(expired: true);
    }
  }

  /// Lets the UI/tests trigger the "session expired" path deterministically
  /// instead of waiting out the real (short, demo-only) token lifetime.
  bool expired = false;
  void debugExpireSession() => logout(expired: true);

  void logout({bool expired = false}) {
    _refreshTimer?.cancel();
    _kycTimer?.cancel();
    this.expired = expired;
    state = null;
  }

  // ---- Biometrics ----

  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasBiometricCredential() async {
    final stored = await _secureStorage.read(key: _biometricUserKey);
    return stored != null;
  }

  /// Which biometric kinds the device offers, so the UI can label its
  /// button "Enable Face ID" vs "Enable Touch ID" instead of a generic
  /// "Enable biometrics" — falls back to an empty list on any platform
  /// error, same as [isBiometricAvailable].
  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> enableBiometric() async {
    final session = state;
    if (session == null) return false;
    final ok = await _authenticateBiometric(
      "Confirm it's you to enable quick sign-in.",
    );
    if (!ok) return false;
    final updatedUser = session.user.copyWith(biometricEnabled: true);
    await _secureStorage.write(
      key: _biometricUserKey,
      value: jsonEncode(_encodeUser(updatedUser)),
    );
    state = session.copyWith(user: updatedUser);
    return true;
  }

  Future<void> disableBiometric() async {
    await _secureStorage.delete(key: _biometricUserKey);
    final session = state;
    if (session != null) {
      state = session.copyWith(
        user: session.user.copyWith(biometricEnabled: false),
      );
    }
  }

  Future<bool> loginWithBiometric() async {
    final stored = await _secureStorage.read(key: _biometricUserKey);
    if (stored == null) return false;
    final ok = await _authenticateBiometric('Sign in to RUN-It');
    if (!ok) return false;
    final user = _decodeUser(jsonDecode(stored) as Map<String, dynamic>);
    state = await _repository.issueSession(user);
    _scheduleSilentRefresh();
    return true;
  }

  Future<bool> _authenticateBiometric(String reason) async {
    try {
      if (!await isBiometricAvailable()) return false;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _encodeUser(UserProfile user) => {
    'id': user.id,
    'name': user.name,
    'contact': user.contact,
    'accountType': user.accountType.name,
    'campusId': user.campusId,
    'classOrGrade': user.classOrGrade,
    'kycStatus': user.kycStatus.name,
    'kycRejectionReason': user.kycRejectionReason,
    'biometricEnabled': user.biometricEnabled,
    'passcodeSet': user.passcodeSet,
    'runnerType': user.runnerType?.name,
    'vehicleType': user.vehicleType?.name,
    'vehiclePlate': user.vehiclePlate,
  };

  UserProfile _decodeUser(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    name: json['name'] as String,
    contact: json['contact'] as String,
    accountType: AccountType.values.byName(json['accountType'] as String),
    campusId: json['campusId'] as String,
    classOrGrade: json['classOrGrade'] as String?,
    kycStatus: KycStatus.values.byName(json['kycStatus'] as String),
    kycRejectionReason: json['kycRejectionReason'] as String?,
    biometricEnabled: json['biometricEnabled'] as bool? ?? false,
    passcodeSet: json['passcodeSet'] as bool? ?? false,
    runnerType: (json['runnerType'] as String?) == null
        ? null
        : RunnerType.values.byName(json['runnerType'] as String),
    vehicleType: (json['vehicleType'] as String?) == null
        ? null
        : VehicleType.values.byName(json['vehicleType'] as String),
    vehiclePlate: json['vehiclePlate'] as String?,
  );

  // ---- Passcode (student login credential) ----

  String _hashPasscode(String passcode) =>
      sha256.convert(utf8.encode('$_passcodeSalt:$passcode')).toString();

  /// Called once, at the end of the Set Passcode step — hashes and stores
  /// the passcode plus a snapshot of the current user (mirrors the
  /// biometric-credential pattern) so a later [loginWithPasscode] on this
  /// device knows both the credential and who it belongs to.
  Future<void> setPasscode(String passcode) async {
    final session = state;
    if (session == null) return;
    final updatedUser = session.user.copyWith(passcodeSet: true);
    await _secureStorage.write(
      key: _passcodeHashKey,
      value: _hashPasscode(passcode),
    );
    await _secureStorage.write(
      key: _passcodeUserKey,
      value: jsonEncode(_encodeUser(updatedUser)),
    );
    state = session.copyWith(user: updatedUser);
  }

  Future<bool> hasStoredPasscode() async {
    final stored = await _secureStorage.read(key: _passcodeHashKey);
    return stored != null;
  }

  /// Never a dead end: a wrong passcode simply returns `false` so the UI
  /// can show a mismatch and let the user retry.
  Future<bool> loginWithPasscode(String passcode) async {
    final storedHash = await _secureStorage.read(key: _passcodeHashKey);
    final storedUser = await _secureStorage.read(key: _passcodeUserKey);
    if (storedHash == null || storedUser == null) return false;
    if (storedHash != _hashPasscode(passcode)) return false;
    final user = _decodeUser(jsonDecode(storedUser) as Map<String, dynamic>);
    state = await _repository.issueSession(user);
    _scheduleSilentRefresh();
    return true;
  }

  // ---- KYC ----

  static const _rejectionReasons = [
    'ID photo was blurry — please retake in better lighting.',
    "The name on the ID doesn't match your profile name.",
    'ID card edges were cut off in the photo.',
  ];

  /// Moves the account to Pending and, after a simulated review delay,
  /// resolves to Verified or Rejected — stand-in for a real review queue
  /// (Task 7 gives that queue an admin surface). Also the only place
  /// [UserProfile.runnerType]/[UserProfile.vehicleType]/
  /// [UserProfile.vehiclePlate] get persisted: the KYC-capture wizard
  /// state they come from is transient and reset right after this call,
  /// so this is the hand-off point before that context is lost — both on
  /// first submission and on every resubmission after a rejection.
  void submitKyc({
    RunnerType? runnerType,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) {
    final session = state;
    if (session == null) return;
    state = session.copyWith(
      user: session.user.copyWith(
        kycStatus: KycStatus.pending,
        clearRejectionReason: true,
        runnerType: runnerType,
        vehicleType: vehicleType,
        vehiclePlate: vehiclePlate,
      ),
    );
    _kycTimer?.cancel();
    _kycTimer = Timer(const Duration(seconds: 4), _resolveKyc);
  }

  /// Lets a runner edit their declared vehicle from Profile after
  /// onboarding — reuses [UserProfile.vehicleType]/[vehiclePlate] rather
  /// than re-running any part of the KYC wizard. Mirrors [enableBiometric]:
  /// if a biometric-login snapshot exists, it's rewritten too so a later
  /// biometric sign-in doesn't resurrect the stale vehicle info.
  Future<void> updateVehicle({
    required VehicleType vehicleType,
    required String? vehiclePlate,
  }) async {
    final session = state;
    if (session == null) return;
    final updatedUser = session.user.copyWith(
      vehicleType: vehicleType,
      vehiclePlate: vehiclePlate,
    );
    if (await _secureStorage.read(key: _biometricUserKey) != null) {
      await _secureStorage.write(
        key: _biometricUserKey,
        value: jsonEncode(_encodeUser(updatedUser)),
      );
    }
    state = session.copyWith(user: updatedUser);
  }

  void _resolveKyc() {
    final session = state;
    if (session == null || session.user.kycStatus != KycStatus.pending) return;
    final rejected = _random.nextDouble() < 0.25;
    state = session.copyWith(
      user: session.user.copyWith(
        kycStatus: rejected ? KycStatus.rejected : KycStatus.verified,
        kycRejectionReason: rejected
            ? _rejectionReasons[_random.nextInt(_rejectionReasons.length)]
            : null,
        clearRejectionReason: !rejected,
      ),
    );
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);
