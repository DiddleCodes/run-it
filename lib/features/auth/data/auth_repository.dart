import '../domain/auth_models.dart';

/// Mock stand-in for a real auth backend. Every method here is exactly
/// where a real HTTP call would go — the shapes returned (session with
/// access/refresh tokens, campus-bound user) are what a real server
/// response would look like, so swapping this out later doesn't ripple
/// through the controller or UI.
class AuthRepository {
  const AuthRepository();

  Future<void> sendOtp(String contact) async {
    await Future.delayed(const Duration(milliseconds: 900));
  }

  /// Any 6-digit code succeeds in this prototype — there is no real SMS/
  /// email delivery to check against.
  Future<bool> verifyOtp(String contact, String code) async {
    await Future.delayed(const Duration(milliseconds: 700));
    return code.length == 6;
  }

  Future<UserProfile> register({
    required String name,
    required String contact,
    required AccountType accountType,
    required String campusId,
    String? classOrGrade,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return UserProfile(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      contact: contact,
      accountType: accountType,
      campusId: campusId,
      classOrGrade: classOrGrade,
    );
  }

  /// Access tokens are deliberately short-lived (25s) purely so the silent
  /// refresh cycle is observable in a demo — a real backend would issue
  /// something like a 15–60 minute access token.
  Future<AuthSession> issueSession(UserProfile user) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    return AuthSession(
      accessToken: 'demo-access-${now.microsecondsSinceEpoch}',
      refreshToken: 'demo-refresh-${now.microsecondsSinceEpoch}',
      expiresAt: now.add(const Duration(seconds: 25)),
      user: user,
    );
  }

  Future<AuthSession> refresh(AuthSession session) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final now = DateTime.now();
    return session.copyWith(
      accessToken: 'demo-access-${now.microsecondsSinceEpoch}',
      expiresAt: now.add(const Duration(seconds: 25)),
    );
  }
}
