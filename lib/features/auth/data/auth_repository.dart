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
    required this.expiresAt,
    required this.userId,
  });

  final String accessToken;
  final DateTime expiresAt;
  final String userId;
}

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
  }) async {
    final json =
        await client.post(
              '/auth/otp/verify',
              body: {
                'contact': contact,
                'code': code,
                'accountType': accountType.name,
                'name': ?name,
              },
            )
            as Map<String, dynamic>;
    final accessToken = json['accessToken'] as String;
    final userId = (json['user'] as Map<String, dynamic>)['id'] as String;
    return OtpVerificationResult(
      accessToken: accessToken,
      expiresAt: _expiryFromJwt(accessToken),
      userId: userId,
    );
  }

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
