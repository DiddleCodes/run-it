import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/data/auth_repository.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/otp_screen.dart';
import 'package:run_it/features/auth/presentation/signup_screen.dart';

/// Stands in for a real backend rejection — a suspended account's OTP
/// verify (or simply a wrong/expired code; the backend deliberately makes
/// these indistinguishable) — without a live server.
class _RejectingAuthRepository extends AuthRepository {
  const _RejectingAuthRepository(this.exception);
  final ApiException exception;

  @override
  Future<void> sendOtp(String contact, {required AccountType accountType}) async {}

  @override
  Future<OtpVerificationResult> verifyOtp({
    required String contact,
    required String code,
    required AccountType accountType,
    String? name,
  }) async {
    throw exception;
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._repository);
  final AuthRepository _repository;
  @override
  AuthSession? build() {
    repository = _repository;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final args = SignupArgs(
    name: 'Ada Student',
    contact: 'ada@campus.edu',
    accountType: AccountType.student,
    campus: kCampuses.first,
  );

  // Task 17: a suspended account's real backend rejection must surface its
  // own message ("Invalid or expired code") — not the generic "Couldn't
  // reach the server" text every other thrown exception here used to
  // collapse into, which would be actively misleading (the server *was*
  // reached; it explicitly rejected the request).
  testWidgets(
    "shows the backend's real rejection message, not a generic connectivity error",
    (tester) async {
      const rejection = ApiException(401, 'Invalid or expired code');
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(const _RejectingAuthRepository(rejection)),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialAppWrapper(child: OtpScreen(args: args)),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final notifications = container.read(appNotificationProvider);
      expect(notifications.map((n) => n.message), contains('Invalid or expired code'));
      expect(
        notifications.map((n) => n.message),
        isNot(contains("Couldn't reach the server. Check your connection and try again.")),
      );
      // Never proceeds to Set Passcode on a rejected verify.
      expect(container.read(authControllerProvider), isNull);
    },
  );
}

/// Minimal `MaterialApp` wrapper — `OtpScreen` needs a `Navigator`/`Theme`
/// context but this test has no router to drive.
class MaterialAppWrapper extends StatelessWidget {
  const MaterialAppWrapper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => MaterialApp(home: child);
}
