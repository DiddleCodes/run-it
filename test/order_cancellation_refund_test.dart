import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';

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

/// An order in `placed` — still inside the cancellation window (before a
/// runner has picked it up).
class _PlacedOrderController extends OrderTrackingController {
  @override
  OrderTrackingSession build() => const OrderTrackingSession(
    stage: OrderStage.placed,
    orderId: 'order-cancel-1',
    orderItems: ['1 × Jollof', '1 × Zobo'],
    total: 3600,
    eateryName: 'Tantalizers',
    deliveryLocationLabel: 'Hostel B',
  );
}

/// An order already picked up — past the cancellation window (food is
/// physically in transit).
class _PickedUpOrderController extends OrderTrackingController {
  @override
  OrderTrackingSession build() => const OrderTrackingSession(
    stage: OrderStage.pickedUp,
    orderId: 'order-cancel-2',
    orderItems: ['1 × Jollof'],
    total: 3000,
    eateryName: 'Tantalizers',
    deliveryLocationLabel: 'Hostel B',
  );
}

class _SucceedingRefundEscrowRepository extends EscrowRepository {
  const _SucceedingRefundEscrowRepository();
  @override
  Future<void> refund({required String orderId, required String token}) async {}
}

class _FailingRefundEscrowRepository extends EscrowRepository {
  const _FailingRefundEscrowRepository();
  @override
  Future<void> refund({required String orderId, required String token}) async {
    throw const ApiException(409, 'Escrow for this order is not held — nothing to refund');
  }
}

class _NoOpBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 0;
}

Widget _harness({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: AppRoutes.orderTracking,
    routes: [
      GoRoute(
        path: AppRoutes.orderTracking,
        builder: (_, _) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: AppRoutes.studentOrders,
        builder: (_, _) => const MyOrdersScreen(),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) =>
          AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

/// The default flutter_test surface (800x600) is too short for the Cancel
/// order button (below the fold of OrderTrackingScreen's content); pin to
/// a realistic phone size instead.
void _setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'cancelling a placed order refunds its escrow and moves it into the Cancelled tab with the real refunded amount',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            orderTrackingProvider.overrideWith(() => _PlacedOrderController()),
            escrowRepositoryProvider.overrideWithValue(
              const _SucceedingRefundEscrowRepository(),
            ),
            walletBalanceProvider.overrideWith(() => _NoOpBalanceWallet()),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Cancel order'), findsOneWidget);
      await tester.tap(find.text('Cancel order'));
      await tester.pump();

      // Confirmation dialog first — cancelling isn't a single accidental tap.
      expect(find.text('Cancel this order?'), findsOneWidget);
      await tester.tap(find.text('Cancel order').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Landed back on My Orders' Cancelled tab territory via the real
      // navigation the cancel action performs.
      expect(find.text('My Orders'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MyOrdersScreen)),
      );
      final cancelled = container.read(cancelledOrdersProvider);
      expect(cancelled, hasLength(1));
      expect(cancelled.first.eateryName, 'Tantalizers');
      expect(cancelled.first.refundedAmount, 3600);

      // The order-tracking session is genuinely cleared, not left dangling.
      expect(container.read(orderTrackingProvider).isActive, isFalse);
    },
  );

  testWidgets(
    'a picked-up order can no longer be cancelled — the window has closed',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            orderTrackingProvider.overrideWith(() => _PickedUpOrderController()),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('Cancel order'), findsNothing);
    },
  );

  testWidgets(
    'a refund failure keeps the order active and surfaces the real backend rejection',
    (tester) async {
      _setPhoneViewport(tester);
      await tester.pumpWidget(
        _harness(
          overrides: [
            authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
            orderTrackingProvider.overrideWith(() => _PlacedOrderController()),
            escrowRepositoryProvider.overrideWithValue(
              const _FailingRefundEscrowRepository(),
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Cancel order'));
      await tester.pump();
      await tester.tap(find.text('Cancel order').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Escrow for this order is not held — nothing to refund'),
        findsOneWidget,
      );
      // Never left OrderTrackingScreen, and the order is still active.
      expect(find.text('Track your order'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(OrderTrackingScreen)),
      );
      expect(container.read(orderTrackingProvider).isActive, isTrue);
      expect(container.read(cancelledOrdersProvider), isEmpty);
    },
  );
}
