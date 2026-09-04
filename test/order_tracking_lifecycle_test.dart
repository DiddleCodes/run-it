import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
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

/// The default flutter_test surface (800x600) is too short for this
/// screen's action button to land on-screen once the order summary card
/// and closing message are all stacked in; pin to a realistic phone size,
/// same convention as the other ordering-flow tests.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _harness() {
  final router = GoRouter(
    initialLocation: AppRoutes.orderTracking,
    routes: [
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const OrderTrackingScreen()),
      GoRoute(path: AppRoutes.menu, builder: (_, _) => const Text('MENU_SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession()))],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  testWidgets(
    'the lifecycle reaches every stage in order, each with the right label and stepper position',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_harness());

      final container = ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)));
      container
          .read(orderTrackingProvider.notifier)
          .placeOrder(
            orderId: 'order-lifecycle-1',
            orderItems: ['1 × Jollof'],
            total: 3000,
            eateryName: 'Tantalizers',
            deliveryLocationLabel: 'Hostel B',
          );
      await tester.pump();
      // AnimatedContainer/AnimatedSwitcher/TweenAnimationBuilder transitions
      // mid-flight — settle each stage before asserting on it.
      await tester.pumpAndSettle();

      expect(container.read(orderTrackingProvider).stage, OrderStage.placed);
      expect(find.text('Order Received'), findsOneWidget);
      expect(find.text('Looking for a runner nearby.'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);

      container.read(orderTrackingProvider.notifier).advanceForTest();
      await tester.pumpAndSettle();
      expect(container.read(orderTrackingProvider).stage, OrderStage.runnerAssigned);
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.text('Cancel order'), findsOneWidget);

      // pickedUp/delivered are no longer timer-driven (Task 11) — they only
      // ever advance via a real verify-pickup/verify-delivery success,
      // which RunnerScanScreen reflects here through these same methods.
      container.read(orderTrackingProvider.notifier).markPickedUp();
      await tester.pumpAndSettle();
      expect(container.read(orderTrackingProvider).stage, OrderStage.pickedUp);
      expect(find.text('En Route'), findsOneWidget);
      // The cancellation window has closed — food is physically in transit.
      expect(find.text('Cancel order'), findsNothing);

      container.read(orderTrackingProvider.notifier).markDelivered();
      await tester.pumpAndSettle();
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);
      expect(find.textContaining('Delivered to Hostel B'), findsOneWidget);
      // Confirmation is a student action, never automatic. Below the fold
      // now that the delivery-PIN card (Task 11) adds height above it.
      await tester.scrollUntilVisible(find.text("I've received my order"), 200);
      expect(find.text("I've received my order"), findsOneWidget);
      expect(find.text('Enjoy your meal!'), findsNothing);
    },
  );

  testWidgets(
    'delivered never auto-advances to confirmed — only the explicit tap does',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_harness());
      final container = ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)));
      container
          .read(orderTrackingProvider.notifier)
          .placeOrder(
            orderId: 'order-lifecycle-2',
            orderItems: ['1 × Jollof'],
            total: 3000,
            eateryName: 'Tantalizers',
            deliveryLocationLabel: 'Hostel B',
          );
      container.read(orderTrackingProvider.notifier)
        ..advanceForTest()
        ..markPickedUp()
        ..markDelivered();
      await tester.pumpAndSettle();
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);

      // Time passing on its own must never flip delivered -> confirmed.
      await tester.pump(const Duration(seconds: 10));
      expect(container.read(orderTrackingProvider).stage, OrderStage.delivered);

      await tester.scrollUntilVisible(find.text("I've received my order"), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text("I've received my order"));
      await tester.pumpAndSettle();

      expect(container.read(orderTrackingProvider).stage, OrderStage.confirmed);
      // Task 30: the confirmed layout is shorter than delivered's (no map/
      // report-a-problem row below the fold any more), but the scroll
      // position from the pre-tap scroll above carries over — far enough
      // that the stepper is genuinely culled out of the sliver list's
      // element tree now (not just off-screen), so neither
      // `find.text('Confirmed')` nor `ensureVisible`/`scrollUntilVisible`
      // (both of which need to already find the target) can bring it
      // back. Jumping the scroll position directly is the only thing that
      // works here.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsWidgets);
      // The rating prompt (Task 14 Part D) comes first — Skip reaches the
      // original closing message without submitting a rating.
      expect(find.text('How was your delivery?'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(find.text('Enjoy your meal!'), findsOneWidget);
      expect(find.text('We look forward to your next order.'), findsOneWidget);
      // The closing moment replaces live-tracking chrome, not adds to it.
      expect(find.text("I've received my order"), findsNothing);
      expect(find.text('Back to menu'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "Back to menu" from the confirmed state resets the session',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(_harness());
      final container = ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)));
      container
          .read(orderTrackingProvider.notifier)
          .placeOrder(
            orderId: 'order-lifecycle-3',
            orderItems: ['1 × Jollof'],
            total: 3000,
            eateryName: 'Tantalizers',
            deliveryLocationLabel: 'Hostel B',
          );
      final notifier = container.read(orderTrackingProvider.notifier)
        ..advanceForTest()
        ..markPickedUp()
        ..markDelivered();
      await tester.pumpAndSettle();
      notifier.confirmDelivery();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Back to menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to menu'));
      await tester.pumpAndSettle();

      expect(find.text('MENU_SCREEN'), findsOneWidget);
      expect(container.read(orderTrackingProvider).isActive, isFalse);
    },
  );
}
