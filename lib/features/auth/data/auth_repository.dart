import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../domain/auth_models.dart';

/// The essentials `AuthController` needs out of a real `/auth/otp/verify`
/// response to build a full [AuthSession] — deliberately not the full
/// backend user object, since only the caller (signup vs. passcode-reset
/// recovery) knows how to assemble the rest of [UserProfile] (campusId,
/// classOrGrade, or an already-known stored snapshot).
class OtpVerificationResult {
  const OtpVerificationResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.campusId,
  });

  final String accessToken;

  /// Task 34: a real, long-lived, rotating refresh token — issued
  /// alongside the (now short-lived) access token so a routine rollover
  /// doesn't force a full re-OTP. See [AuthRepository.refresh].
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;

  /// Task 26: the real, backend-derived (student) or admin-assigned
  /// (runner) campus — null for a runner nobody has assigned one to yet.
  /// Never client-supplied.
  final String? campusId;
}

/// Task 34: what `POST /auth/refresh` hands back — a fresh access token
/// plus, via rotation, a brand-new refresh token that replaces the one
/// just spent. The old refresh token stops working the instant this
/// response is issued (server-side revocation), so callers must persist
/// [refreshToken] immediately, not the one they called with.
class RefreshResult {
  const RefreshResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
}

/// Task 29: what a real `GET /auth/me` response carries — the KYC fields
/// AuthController.refreshProfile needs to correct a possibly-stale locally
/// cached [UserProfile] against whatever the backend actually says right
/// now (see that method's own doc comment). `kycStatus` is null for a
/// student (never has a RunnerKyc row) and for a runner who hasn't
/// submitted anything yet — both map to [KycStatus.none] client-side.
class MeResult {
  const MeResult({
    required this.kycStatus,
    this.kycRejectionReason,
    this.runnerType,
    this.vehicleType,
    this.vehiclePlate,
  });

  final KycStatus kycStatus;
  final String? kycRejectionReason;
  final RunnerType? runnerType;
  final VehicleType? vehicleType;
  final String? vehiclePlate;
}

KycStatus _kycStatusFromWire(String? wire) => switch (wire) {
  'pending' => KycStatus.pending,
  'approved' => KycStatus.verified,
  'rejected' => KycStatus.rejected,
  _ => KycStatus.none,
};

/// Task 17: the mobile student/runner flow's real, backend-verified
/// session issuance — a real `POST /auth/otp/request` + `POST
/// /auth/otp/verify` pair, replacing both the old client-only "any
/// 6-digit code succeeds" stopgap and the `/auth/dev-token` bridge that
/// used to mint the session afterward. `verifyOtp`'s response is signed
/// the same way the web dashboard's `AuthService.login()` signs one, tied
/// to a real `User` row, and rejects a suspended account with the same
/// generic message a wrong code gets.
class AuthRepository {
  const AuthRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<void> sendOtp(String contact, {required AccountType accountType}) async {
    await client.post(
      '/auth/otp/request',
      body: {'contact': contact, 'accountType': accountType.name},
    );
  }

  /// Throws [ApiException] (backend message: "Invalid or expired code")
  /// on a wrong/expired/already-used code, or a suspended account — the
  /// backend deliberately makes these indistinguishable, same as the
  /// dashboard's login rejection.
  Future<OtpVerificationResult> verifyOtp({
    required String contact,
    required String code,
    required AccountType accountType,
    String? name,
    String? phone,
  }) async {
    final json =
        await client.post(
              '/auth/otp/verify',
              body: {
                'contact': contact,
                'code': code,
                'accountType': accountType.name,
                'name': ?name,
                'phone': ?phone,
              },
            )
            as Map<String, dynamic>;
    final accessToken = json['accessToken'] as String;
    final user = json['user'] as Map<String, dynamic>;
    return OtpVerificationResult(
      accessToken: accessToken,
      refreshToken: json['refreshToken'] as String,
      expiresAt: _expiryFromJwt(accessToken),
      userId: user['id'] as String,
      campusId: user['campusId'] as String?,
    );
  }

  /// Task 34: exchanges a still-valid refresh token for a fresh access
  /// token and, via rotation, a fresh refresh token — what
  /// `AuthController.handleUnauthorized`/`_loadPersistedSession` call to
  /// resume a session silently instead of forcing a full re-OTP. Throws
  /// [ApiException] (401) when the refresh token is unknown, already used,
  /// expired, or its owning account has since been suspended — the caller
  /// must treat all of those as "needs a real re-authentication," same as
  /// every other generic rejection in this app's auth flow.
  Future<RefreshResult> refresh({required String refreshToken}) async {
    final json =
        await client.post('/auth/refresh', body: {'refreshToken': refreshToken})
            as Map<String, dynamic>;
    final accessToken = json['accessToken'] as String;
    return RefreshResult(
      accessToken: accessToken,
      refreshToken: json['refreshToken'] as String,
      expiresAt: _expiryFromJwt(accessToken),
    );
  }

  /// Task 34: server-side revocation — the refresh token this device was
  /// holding can never be replayed afterward, unlike a client-only "forget
  /// it locally" logout. Resolves the same generic way whether or not the
  /// token was still valid; the caller (AuthController.logout) treats a
  /// network failure here as best-effort, not a reason to block signing
  /// out of this device.
  Future<void> logout({required String refreshToken}) async {
    await client.post('/auth/logout', body: {'refreshToken': refreshToken});
  }

  /// Task 29: the real profile-refresh call — was previously wired up on
  /// the backend (`GET /auth/me`) but never actually called by this app.
  /// Now the source of truth [AuthController.refreshProfile] polls while a
  /// runner's KYC is under review, and re-checks right after a biometric
  /// resume so a stale locally cached status can never outlive an admin
  /// decision made while the app was closed.
  Future<MeResult> fetchMe({required String token}) async {
    final json = await client.get('/auth/me', token: token) as Map<String, dynamic>;
    return MeResult(
      kycStatus: _kycStatusFromWire(json['kycStatus'] as String?),
      kycRejectionReason: json['kycRejectionReason'] as String?,
      runnerType: (json['runnerType'] as String?) == null
          ? null
          : RunnerType.values.byName(_camelCase(json['runnerType'] as String)),
      vehicleType: (json['vehicleType'] as String?) == null
          ? null
          : VehicleType.values.byName(json['vehicleType'] as String),
      vehiclePlate: json['vehiclePlate'] as String?,
    );
  }

  /// `RunnerKycRunnerType`'s wire values are snake_case
  /// (`student_runner`/`independent_rider`); [RunnerType]'s Dart enum
  /// names are camelCase — converts the one real shape the backend ever
  /// sends here rather than a general-purpose snake-to-camel helper.
  String _camelCase(String snakeCase) => switch (snakeCase) {
    'student_runner' => 'studentRunner',
    'independent_rider' => 'independentRider',
    _ => snakeCase,
  };

  /// Reads the real `exp` claim out of the JWT rather than guessing/
  /// hardcoding a duration client-side — there's no token-introspection
  /// endpoint, but the token itself already carries the answer.
  DateTime _expiryFromJwt(String token) {
    final fallback = DateTime.now().add(const Duration(days: 1));
    final parts = token.split('.');
    if (parts.length != 3) return fallback;
    try {
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
              as Map<String, dynamic>;
      final exp = payload['exp'] as int?;
      if (exp == null) return fallback;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return fallback;
    }
  }
}
