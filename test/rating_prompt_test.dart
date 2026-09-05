import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/ratings_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _studentSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'student-1',
    name: 'Ayanfe O.',
    contact: 'ayanfe@student.ui.edu.ng',
    accountType: AccountType.student,
    campusId: 'ui',
  ),
);

void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _RecordingRatingsRepository extends RatingsRepository {
  _RecordingRatingsRepository({this.throwOnRate});
  final ApiException? throwOnRate;
  String? lastOrderId;
  int? lastRunnerStars;
  int? lastVendorStars;
  bool called = false;

  @override
  Future<void> rate({
    required String orderId,
    int? runnerStars,
    String? runnerComment,
    int? vendorStars,
    String? vendorComment,
    required String token,
  }) async {
    if (throwOnRate != null) throw throwOnRate!;
    called = true;
    lastOrderId = orderId;
    lastRunnerStars = runnerStars;
    lastVendorStars = vendorStars;
  }
}

Widget _harness(RatingsRepository repo) {
  final router = GoRouter(
    initialLocation: AppRoutes.orderTracking,
    routes: [
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const OrderTrackingScreen()),
      GoRoute(path: AppRoutes.menu, builder: (_, _) => const Text('MENU_SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
      ratingsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

Future<ProviderContainer> _reachConfirmed(WidgetTester tester, Widget harness, String orderId) async {
  await tester.pumpWidget(harness);
  final container = ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)));
  container
      .read(orderTrackingProvider.notifier)
      .placeOrder(orderId: orderId, orderItems: const ['1 × Jollof'], total: 3000, eateryName: 'Tantalizers', deliveryLocationLabel: 'Hostel B');
  container.read(orderTrackingProvider.notifier)
    ..advanceForTest()
    ..markPickedUp()
    ..markDelivered();
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text("I've received my order"), 200);
  await tester.pumpAndSettle();
  await tester.tap(find.text("I've received my order"));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('Rating prompt (Task 14 Part D, extended by Task 48 to also rate the restaurant)', () {
    testWidgets('submitting a real rating for both the runner and the restaurant shows Thanks, then the closing message', (
      tester,
    ) async {
      _setPhoneViewport(tester);
      final repo = _RecordingRatingsRepository();
      await _reachConfirmed(tester, _harness(repo), 'order-rating-1');

      expect(find.text('How was your order?'), findsOneWidget);
      expect(find.text('Your runner'), findsOneWidget);
      expect(find.text('Tantalizers'), findsOneWidget);
      // No submission yet — the repository must not have been called just
      // from reaching this screen.
      expect(repo.called, isFalse);

      // Two rows of 5 stars each: runner first (indices 0-4), then the
      // restaurant (indices 5-9) — tapping the runner's 5th star fills all
      // 5 of its icons, so the restaurant row's own stars re-index to 0-4
      // for the next find.
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(4)); // runner: 5th star
      await tester.pump();
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(2)); // restaurant: 3rd star (of its own row)
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump();

      // Reflects the real, confirmed backend response — not an optimistic
      // jump straight to the closing message.
      expect(find.text('Thanks for your feedback!'), findsOneWidget);
      expect(repo.lastOrderId, 'order-rating-1');
      expect(repo.lastRunnerStars, 5);
      expect(repo.lastVendorStars, 3);

      // The brief confirmation auto-advances into the original closing
      // message after its own short delay.
      await tester.pump(const Duration(milliseconds: 950));
      expect(find.text('Enjoy your meal!'), findsOneWidget);
      // Lets the "Thanks" widget's own one-shot entrance animation
      // (flutter_animate) resolve before teardown — it was disposed
      // mid-flight by the phase transition above.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('rating only the restaurant (leaving the runner unrated) still submits a real, partial rating', (tester) async {
      _setPhoneViewport(tester);
      final repo = _RecordingRatingsRepository();
      await _reachConfirmed(tester, _harness(repo), 'order-rating-partial');

      // Restaurant row only — 4th star of the second row.
      await tester.tap(find.byIcon(Icons.star_border_rounded).at(8));
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump();

      expect(repo.called, isTrue);
      expect(repo.lastRunnerStars, isNull);
      expect(repo.lastVendorStars, 4);

      // Drains the "Thanks" -> closing-message timer so no pending timer
      // survives past this test's own teardown.
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Skip reaches the closing message without ever calling the backend', (tester) async {
      _setPhoneViewport(tester);
      final repo = _RecordingRatingsRepository();
      await _reachConfirmed(tester, _harness(repo), 'order-rating-2');

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Enjoy your meal!'), findsOneWidget);
      expect(repo.called, isFalse);
    });

    testWidgets('an already-rated (409) rejection is treated as a soft success, not an error', (tester) async {
      _setPhoneViewport(tester);
      final repo = _RecordingRatingsRepository(throwOnRate: const ApiException(409, 'This order has already been rated'));
      await _reachConfirmed(tester, _harness(repo), 'order-rating-3');

      await tester.tap(find.byIcon(Icons.star_border_rounded).first); // 1st star, runner row
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump();

      // No raw/alarming error banner for what isn't really a failure from
      // the student's perspective.
      expect(find.text('This order has already been rated'), findsNothing);
      expect(find.text('Thanks for your feedback!'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 950));
      expect(find.text('Enjoy your meal!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a real backend failure surfaces its own message and stays on the rating prompt', (tester) async {
      _setPhoneViewport(tester);
      final repo = _RecordingRatingsRepository(throwOnRate: const ApiException(500, 'Something went wrong on our end'));
      await _reachConfirmed(tester, _harness(repo), 'order-rating-4');

      await tester.tap(find.byIcon(Icons.star_border_rounded).first);
      await tester.pump();
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Something went wrong on our end'), findsOneWidget);
      expect(find.text('How was your order?'), findsOneWidget);
      expect(find.text('Thanks for your feedback!'), findsNothing);
    });
  });
}
