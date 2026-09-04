import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/network/runner_kyc_repository.dart';
import '../../../core/network/uploads_repository.dart';
import '../../../core/widgets/app_notification.dart';
import '../data/auth_repository.dart';
import '../domain/auth_models.dart';
import 'kyc_flow_controller.dart' show IdType;

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
// Task 34: the real refresh token that lets a persisted session outlive
// its (now short-lived, 1h) access token — see _loadPersistedSession and
// handleUnauthorized, both of which fall back to a real network refresh
// via this rather than declaring the session dead the moment
// [_sessionExpiryKey] has passed.
const _sessionRefreshTokenKey = 'runit_session_refresh_token_v1';

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
  /// Task 29: same reassignable-for-tests convention as [repository] —
  /// used by [submitKycForReview] to upload the three real KYC photos.
  UploadsRepository uploads = const UploadsRepository();
  /// Task 29: same convention as [repository]/[uploads] — used by
  /// [submitKycForReview] to register the uploaded photo URLs for review.
  RunnerKycRepository runnerKyc = const RunnerKycRepository();
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
    String? classOrGrade,
    String? phone,
  }) async {
    final result = await repository.verifyOtp(
      contact: contact,
      code: code,
      accountType: accountType,
      name: name,
      phone: phone,
    );
    state = AuthSession(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      expiresAt: result.expiresAt,
      user: UserProfile(
        id: result.userId,
        name: name,
        contact: contact,
        accountType: accountType,
        // Task 26: the real, backend-derived/admin-assigned campus — never
        // client-supplied. Null for a fresh runner/restaurant account
        // nobody has assigned one to yet.
        campusId: result.campusId,
        classOrGrade: classOrGrade,
        // Task 28: a runner's own phone, client-supplied same as
        // classOrGrade above — never echoed back by the backend, but the
        // backend only ever persists it on first verify anyway, so this
        // matches what's actually stored.
        phone: phone,
      ),
    );
  }

  Future<void> _persistSession(AuthSession session) async {
    await _secureStorage.write(key: _sessionTokenKey, value: session.accessToken);
    await _secureStorage.write(
      key: _sessionRefreshTokenKey,
      value: session.refreshToken,
    );
    await _secureStorage.write(
      key: _sessionExpiryKey,
      value: session.expiresAt.toIso8601String(),
    );
  }

  /// Null when there's nothing stored at all — the caller
  /// (loginWithPasscode/loginWithBiometric) must treat that as "needs a
  /// full re-authentication," never re-mint a token out of thin air for
  /// [user]. If the persisted *access* token has expired (routine now that
  /// it's short-lived, 1h — see AuthService's own TTL comment), this
  /// silently spends the persisted *refresh* token to mint a fresh one
  /// instead of giving up — only returns null from that path if the
  /// refresh call itself is rejected (expired/revoked/suspended) or no
  /// refresh token was ever persisted (a pre-Task-34 session).
  Future<AuthSession?> _loadPersistedSession(UserProfile user) async {
    final token = await _secureStorage.read(key: _sessionTokenKey);
    final refreshToken = await _secureStorage.read(key: _sessionRefreshTokenKey);
    final expiryRaw = await _secureStorage.read(key: _sessionExpiryKey);
    if (token == null || expiryRaw == null) return null;
    final expiresAt = DateTime.tryParse(expiryRaw);
    if (expiresAt == null) return null;
    final session = AuthSession(
      accessToken: token,
      refreshToken: refreshToken ?? token,
      expiresAt: expiresAt,
      user: user,
    );
    if (!session.isExpired) return session;
    if (refreshToken == null) return null;
    return _attemptRefresh(session);
  }

  /// Task 34: the one place a real, server-verified refresh is attempted —
  /// shared by [_loadPersistedSession] (a cold resume finding a
  /// time-expired access token) and [handleUnauthorized] (a live request
  /// getting rejected mid-session). Returns null on any failure
  /// (unreachable backend, or the backend genuinely rejecting the refresh
  /// token — expired, already rotated, or the account got suspended) —
  /// callers must treat that as "this session cannot be silently
  /// recovered," never retry with the same token again.
  ///
  /// De-duplicated via [_refreshInFlight]: two callers racing (e.g. two
  /// screens' calls both getting a 401 around the same moment) share one
  /// real network call instead of each spending the same not-yet-rotated
  /// refresh token — the second of two *independent* calls would otherwise
  /// find it already rotated by the first and be wrongly treated as an
  /// unrecoverable session.
  Future<AuthSession?>? _refreshInFlight;

  Future<AuthSession?> _attemptRefresh(AuthSession current) {
    return _refreshInFlight ??= _doRefresh(current).whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<AuthSession?> _doRefresh(AuthSession current) async {
    try {
      final result = await repository.refresh(refreshToken: current.refreshToken);
      final refreshed = AuthSession(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        expiresAt: result.expiresAt,
        user: current.user,
      );
      await _persistSession(refreshed);
      return refreshed;
    } catch (_) {
      return null;
    }
  }

  /// Lets the UI/tests trigger the "session expired" path deterministically
  /// instead of waiting out the real token's day-long lifetime.
  bool expired = false;
  void debugExpireSession() => logout(expired: true);

  /// Task 17: the single place a backend-rejected access token (expired,
  /// or a request rejected mid-session — [ApiClient.onUnauthorized] never
  /// distinguishes why) is handled, instead of a raw error left for
  /// whatever screen happened to be mid-request. Wired once, at app
  /// startup (`main.dart`), to every `ApiClient` call. Idempotent:
  /// already-logged-out is a no-op, so a burst of concurrent requests
  /// failing at once only ever resolves once (via [_refreshInFlight]).
  ///
  /// Task 34: a real, server-verified silent refresh (via
  /// [_attemptRefresh]) is tried *first* — only if that itself fails
  /// (expired, already rotated, or the account got suspended) does this
  /// fall through to the old hard-logout behavior below. This is
  /// deliberately **not** a resurrection of the dev-token-based silent
  /// refresh Task 17 removed: that endpoint (`/auth/dev-token`) is
  /// disabled outside development ([DevOnlyGuard]) and could mint a
  /// session for *any* userId with no proof of prior authentication.
  /// `/auth/refresh` only ever succeeds against a real, hashed, single-use,
  /// rotating refresh token this exact session was issued at OTP-verify
  /// time — one already-suspended, already-replayed, or already-expired
  /// refresh token is rejected the same generic way any other invalid
  /// session is, and AdminUsersService.suspend revokes it server-side the
  /// instant an admin acts, so a suspended account can't ride this path to
  /// a fresh access token either.
  ///
  /// A genuinely failed refresh still clears the *persisted* session, same
  /// as before — the backend has just said this exact refresh token is no
  /// good, which the very next passcode/biometric unlock must not
  /// silently retry.
  Future<void> handleUnauthorized() async {
    final session = state;
    if (session == null) return;

    final refreshed = await _attemptRefresh(session);
    if (refreshed != null) {
      state = refreshed;
      return;
    }

    await Future.wait([
      _secureStorage.delete(key: _sessionTokenKey),
      _secureStorage.delete(key: _sessionExpiryKey),
      _secureStorage.delete(key: _sessionRefreshTokenKey),
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
      // Task 34: real server-side revocation, not just clearing local
      // storage — the refresh token this device was holding can never be
      // replayed after this. Best-effort: a network failure must never
      // block the user from actually signing out of this device, so a
      // rejected/unreachable call here is swallowed rather than left to
      // interrupt the storage-clearing below (the token then simply
      // expires naturally, at worst, in REFRESH_TOKEN_TTL_DAYS).
      final session = state;
      if (session != null) {
        try {
          await repository.logout(refreshToken: session.refreshToken);
        } catch (_) {
          // See doc comment above.
        }
      }
      await Future.wait([
        _secureStorage.delete(key: _sessionTokenKey),
        _secureStorage.delete(key: _sessionExpiryKey),
        _secureStorage.delete(key: _sessionRefreshTokenKey),
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
    // Task 29: a runner may have been approved/rejected by an admin while
    // this device's biometric snapshot was last written — refresh against
    // the real backend status now rather than trusting whatever was cached
    // at [enableBiometric] time. Best-effort: [refreshProfile] no-ops on a
    // network failure, so this never blocks a resume that would otherwise
    // succeed offline.
    if (user.accountType == AccountType.runner) {
      await refreshProfile();
    }
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
    'phone': user.phone,
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
    campusId: json['campusId'] as String?,
    classOrGrade: json['classOrGrade'] as String?,
    phone: json['phone'] as String?,
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
      refreshToken: result.refreshToken,
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

  /// Task 29: the light-KYC (student) path only now — moves the account to
  /// Pending and, after a simulated review delay, resolves to Verified or
  /// Rejected. There's still no real backend concept of student KYC (out
  /// of this task's scope — see its own report), so this stand-in stays
  /// exactly as it was. Runner KYC no longer calls this: see
  /// [submitKycForReview] for the real, backend-verified equivalent.
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

  /// Task 29: the real runner KYC submission — uploads the three captured
  /// photos (same presign-then-PUT flow DeliveryProofCaptureScreen already
  /// uses), registers them against `POST /runner-kyc/submit`, then reflects
  /// the real `pending` status locally. Unlike [submitKyc], there is no
  /// local Random()/Timer resolution here — [KycStatusScreen] polls
  /// [refreshProfile] for the real admin decision. Returns false (and
  /// leaves the caller's screen in place) on any upload/network failure —
  /// this must never optimistically claim a submission succeeded.
  Future<bool> submitKycForReview({
    required RunnerType runnerType,
    required IdType idType,
    required Uint8List idImage,
    required Uint8List selfieImage,
    Uint8List? vehiclePhoto,
    VehicleType? vehicleType,
    String? vehiclePlate,
  }) async {
    final session = state;
    if (session == null) return false;
    final token = session.accessToken;

    try {
      final idPhotoUrl = await uploads.uploadImage(
        bytes: idImage,
        purpose: 'runner-kyc-id',
        contentType: 'image/jpeg',
        token: token,
      );
      final selfiePhotoUrl = await uploads.uploadImage(
        bytes: selfieImage,
        purpose: 'runner-kyc-selfie',
        contentType: 'image/jpeg',
        token: token,
      );
      String? vehiclePhotoUrl;
      if (vehiclePhoto != null) {
        vehiclePhotoUrl = await uploads.uploadImage(
          bytes: vehiclePhoto,
          purpose: 'runner-kyc-vehicle',
          contentType: 'image/jpeg',
          token: token,
        );
      }
      await runnerKyc.submit(
        token: token,
        runnerType: runnerType,
        idType: idType,
        idPhotoUrl: idPhotoUrl,
        selfiePhotoUrl: selfiePhotoUrl,
        vehiclePhotoUrl: vehiclePhotoUrl,
        vehicleType: vehicleType,
        vehiclePlate: vehiclePlate,
      );
    } catch (_) {
      return false;
    }

    // Re-read state rather than trusting the captured `session` — the
    // uploads above are real network round-trips the user could have
    // logged out during.
    final current = state;
    if (current == null) return false;
    state = current.copyWith(
      user: current.user.copyWith(
        kycStatus: KycStatus.pending,
        clearRejectionReason: true,
        runnerType: runnerType,
        vehicleType: vehicleType,
        vehiclePlate: vehiclePlate,
      ),
    );
    return true;
  }

  /// Task 29: pulls the real KYC status (and any admin rejection reason)
  /// from the backend — the one place a possibly-stale locally cached
  /// [UserProfile.kycStatus] (e.g. resumed via biometric login from before
  /// an admin decision landed) gets corrected. A no-op on any network
  /// failure — polling callers simply retry on their next tick rather than
  /// surfacing a transient error.
  Future<void> refreshProfile() async {
    final session = state;
    if (session == null) return;
    final MeResult result;
    try {
      result = await repository.fetchMe(token: session.accessToken);
    } catch (_) {
      return;
    }
    final current = state;
    if (current == null) return;
    state = current.copyWith(
      user: current.user.copyWith(
        kycStatus: result.kycStatus,
        kycRejectionReason: result.kycRejectionReason,
        clearRejectionReason: result.kycRejectionReason == null,
        runnerType: result.runnerType,
        vehicleType: result.vehicleType,
        vehiclePlate: result.vehiclePlate,
      ),
    );
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
