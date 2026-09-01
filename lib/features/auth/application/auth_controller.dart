import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/widgets/app_notification.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';

const _biometricUserKey = 'runit_biometric_user_v1';
const _passcodeHashKey = 'runit_passcode_hash_v1';
const _passcodeUserKey = 'runit_passcode_user_v1';
// A fixed pepper, not a per-user salt — this is a demo-only local secret
// store (device-bound via FlutterSecureStorage), not a multi-user server
// database where salting defends against a leaked hash table.
const _passcodeSalt = 'runit_passcode_pepper_v1';

// Task 17: the real, backend-issued session token — persisted so
// passcode/biometric unlock can resume a still-valid session locally
// (no network call) instead of blindly re-minting one via the now
// production-disabled dev-token bridge. Written at setPasscode()/
// enableBiometric() time (the same moments the credential snapshots
// above are written), not at OTP-verify time — whatever session is live
// when a quick-unlock credential is set up is exactly what that
// credential should resume later.
const _sessionTokenKey = 'runit_session_token_v1';
const _sessionExpiryKey = 'runit_session_expiry_v1';

/// Thrown by [AuthController.loginWithPasscode]/[loginWithBiometric] when
/// the local credential check passes but there's no still-valid persisted
/// session to resume (it expired, or Task 17's [AuthController.handleUnauthorized]
/// cleared it after a suspension). The caller must route to a full
/// re-authentication (OTP) — retrying the same passcode/biometric can
/// never fix this.
class SessionRecoveryRequiredException implements Exception {
  const SessionRecoveryRequiredException();
}

class AuthController extends Notifier<AuthSession?> {
  /// Deliberately not private/final — tests that need to exercise real
  /// controller logic (passcode hashing, biometric-credential storage) but
  /// stub out the network boundary reassign this in a subclass's `build()`,
  /// mirroring how `_FakeAuthController` subclasses elsewhere in this app
  /// override individual methods rather than requiring constructor
  /// injection (which `NotifierProvider` can't supply — it always calls
  /// `AuthController.new` with no arguments).
  AuthRepository repository = const AuthRepository();
  final _localAuth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage();
  final _random = Random();
  Timer? _kycTimer;

  @override
  AuthSession? build() {
    ref.onDispose(() {
      _kycTimer?.cancel();
    });
    return null;
  }

  Future<void> sendOtp(String contact, {required AccountType accountType}) =>
      repository.sendOtp(contact, accountType: accountType);

  /// Throws [ApiException] on a wrong/expired code or a suspended account
  /// (the backend deliberately makes these indistinguishable) — the
  /// caller shows the backend's own message rather than a hardcoded one.
  Future<void> verifyOtpAndLogin({
    required String contact,
    required String code,
    required String name,
    required AccountType accountType,
    required String campusId,
    String? classOrGrade,
  }) async {
    final result = await repository.verifyOtp(
      contact: contact,
      code: code,
      accountType: accountType,
      name: name,
    );
    state = AuthSession(
      accessToken: result.accessToken,
      // The backend has no distinct refresh-token concept — see
      // AuthRepository's own doc comment.
      refreshToken: result.accessToken,
      expiresAt: result.expiresAt,
      user: UserProfile(
        id: result.userId,
        name: name,
        contact: contact,
        accountType: accountType,
        campusId: campusId,
        classOrGrade: classOrGrade,
      ),
    );
  }

  Future<void> _persistSession(AuthSession session) async {
    await _secureStorage.write(key: _sessionTokenKey, value: session.accessToken);
    await _secureStorage.write(
      key: _sessionExpiryKey,
      value: session.expiresAt.toIso8601String(),
    );
  }

  /// Null when there's nothing stored, or what's stored has since expired
  /// — either way, the caller (loginWithPasscode/loginWithBiometric) must
  /// treat that as "needs a full re-authentication," never re-mint a
  /// token out of thin air for [user].
  Future<AuthSession?> _loadPersistedSession(UserProfile user) async {
    final token = await _secureStorage.read(key: _sessionTokenKey);
    final expiryRaw = await _secureStorage.read(key: _sessionExpiryKey);
    if (token == null || expiryRaw == null) return null;
    final expiresAt = DateTime.tryParse(expiryRaw);
    if (expiresAt == null) return null;
    final session = AuthSession(
      accessToken: token,
      refreshToken: token,
      expiresAt: expiresAt,
      user: user,
    );
    return session.isExpired ? null : session;
  }

  /// Lets the UI/tests trigger the "session expired" path deterministically
  /// instead of waiting out the real token's day-long lifetime.
  bool expired = false;
  void debugExpireSession() => logout(expired: true);

  /// Task 17: the single place a backend-confirmed-invalid session
  /// (expired, or suspended mid-session — [ApiClient.onUnauthorized]
  /// never distinguishes which) becomes a clean logout instead of a raw
  /// error left for whatever screen happened to be mid-request. Wired
  /// once, at app startup (`main.dart`), to every `ApiClient` call.
  /// Idempotent: already-logged-out is a no-op, so a burst of concurrent
  /// requests failing at once only logs out and notifies once.
  ///
  /// Unlike a plain [logout] (`expired: true`, e.g. a genuinely-elapsed
  /// day-long token after an app relaunch), this also clears the
  /// *persisted* session — the backend has just said this exact token is
  /// no good, which a suspended-but-not-yet-time-expired token wouldn't
  /// otherwise reveal locally. Without this, the very next passcode/
  /// biometric unlock would silently reload the same bad token and hit
  /// the same rejection again in a loop instead of routing to a real
  /// re-authentication.
  Future<void> handleUnauthorized() async {
    if (state == null) return;
    await Future.wait([
      _secureStorage.delete(key: _sessionTokenKey),
      _secureStorage.delete(key: _sessionExpiryKey),
    ]);
    await logout(expired: true);
    ref
        .read(appNotificationProvider.notifier)
        .error('Your session has ended. Please sign in again.');
  }

  /// An *expired* logout (app relaunch losing the in-memory session, a
  /// debug trigger, or [handleUnauthorized] which separately also clears
  /// the persisted token) drops the in-memory session but keeps the
  /// stored passcode/biometric credentials *and* — unless
  /// [handleUnauthorized] already cleared it — the persisted session
  /// token. That's exactly what lets [WelcomeBackScreen] offer a quick
  /// way back in: [loginWithPasscode]/[loginWithBiometric] resume that
  /// persisted token locally (no network call) when it's still valid, or
  /// discover (via [_loadPersistedSession] returning null) that a real
  /// re-authentication is needed when it isn't.
  ///
  /// An *explicit* logout (the "Log out" row on every profile/pending
  /// screen) is different: the user is deliberately signing out of this
  /// device, so it wipes every stored credential too — the persisted
  /// session token, passcode hash, the passcode's user snapshot, and any
  /// biometric-login snapshot — not just this in-memory session. Without
  /// this, "Log out" was really just "hide the app until you re-enter
  /// your passcode," which isn't what a destructive "sign out" action
  /// should mean.
  Future<void> logout({bool expired = false}) async {
    _kycTimer?.cancel();
    this.expired = expired;
    if (!expired) {
      await Future.wait([
        _secureStorage.delete(key: _sessionTokenKey),
        _secureStorage.delete(key: _sessionExpiryKey),
        _secureStorage.delete(key: _biometricUserKey),
        _secureStorage.delete(key: _passcodeHashKey),
        _secureStorage.delete(key: _passcodeUserKey),
      ]);
    }
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
    final updatedSession = session.copyWith(user: updatedUser);
    await _persistSession(updatedSession);
    state = updatedSession;
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

  /// Throws [SessionRecoveryRequiredException] when the biometric check
  /// itself passes but there's no still-valid persisted session to
  /// resume — see the exception's own doc comment.
  Future<bool> loginWithBiometric() async {
    final stored = await _secureStorage.read(key: _biometricUserKey);
    if (stored == null) return false;
    final ok = await _authenticateBiometric('Sign in to RUN-It');
    if (!ok) return false;
    final user = _decodeUser(jsonDecode(stored) as Map<String, dynamic>);
    final session = await _loadPersistedSession(user);
    if (session == null) throw const SessionRecoveryRequiredException();
    state = session;
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
    final updatedSession = session.copyWith(user: updatedUser);
    await _persistSession(updatedSession);
    state = updatedSession;
  }

  Future<bool> hasStoredPasscode() async {
    final stored = await _secureStorage.read(key: _passcodeHashKey);
    return stored != null;
  }

  /// The contact (email/phone) of whichever user's passcode is stored on
  /// this device, if any — [WelcomeBackScreen]'s "Forgot passcode?" link
  /// needs it to know who to re-verify via OTP before it can even show
  /// that flow. Null when no passcode has ever been set on this device.
  Future<String?> storedPasscodeContact() async {
    final stored = await _secureStorage.read(key: _passcodeUserKey);
    if (stored == null) return null;
    return _decodeUser(jsonDecode(stored) as Map<String, dynamic>).contact;
  }

  /// Task 20: the account type of whichever user's passcode is stored on
  /// this device — [WelcomeBackScreen]'s "Forgot passcode?" recovery needs
  /// it alongside [storedPasscodeContact] so a resend on the recovery OTP
  /// screen knows whether to route through real email delivery or the
  /// runner phone path. Null exactly when [storedPasscodeContact] is null.
  Future<AccountType?> storedPasscodeAccountType() async {
    final stored = await _secureStorage.read(key: _passcodeUserKey);
    if (stored == null) return null;
    return _decodeUser(jsonDecode(stored) as Map<String, dynamic>).accountType;
  }

  /// "Forgot passcode?" recovery: re-verifies identity via a real OTP
  /// round-trip (the same backend endpoint signup uses) against the
  /// contact already on file for this device's stored passcode
  /// credential, then re-issues a real session for that stored user —
  /// mirrors [loginWithPasscode]'s tail, just gated on a fresh OTP
  /// instead of the (now-forgotten) passcode hash. Once this returns
  /// true, the caller has an active session again and can route into
  /// [SetPasscodeScreen] (`isChangingExisting: true`), whose own
  /// [setPasscode] call is what actually persists this fresh session for
  /// next time. Throws [ApiException] on a wrong/expired code or a
  /// suspended account, same as [verifyOtpAndLogin].
  Future<bool> recoverSessionForPasscodeReset({
    required String contact,
    required String code,
  }) async {
    final storedUserJson = await _secureStorage.read(key: _passcodeUserKey);
    if (storedUserJson == null) return false;
    final storedUser = _decodeUser(
      jsonDecode(storedUserJson) as Map<String, dynamic>,
    );
    final result = await repository.verifyOtp(
      contact: contact,
      code: code,
      accountType: storedUser.accountType,
    );
    state = AuthSession(
      accessToken: result.accessToken,
      refreshToken: result.accessToken,
      expiresAt: result.expiresAt,
      user: storedUser,
    );
    return true;
  }

  /// Never a dead end: a wrong passcode simply returns `false` so the UI
  /// can show a mismatch and let the user retry. Throws
  /// [SessionRecoveryRequiredException] when the passcode itself is
  /// correct but there's no still-valid persisted session to resume.
  Future<bool> loginWithPasscode(String passcode) async {
    final storedHash = await _secureStorage.read(key: _passcodeHashKey);
    final storedUser = await _secureStorage.read(key: _passcodeUserKey);
    if (storedHash == null || storedUser == null) return false;
    if (storedHash != _hashPasscode(passcode)) return false;
    final user = _decodeUser(jsonDecode(storedUser) as Map<String, dynamic>);
    final session = await _loadPersistedSession(user);
    if (session == null) throw const SessionRecoveryRequiredException();
    state = session;
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
