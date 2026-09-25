import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/domain/order_decline.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/order_detail_screen.dart';
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

OrderHistoryEntry _order({
  required String status,
  String paymentMethod = 'wallet',
  OrderDeclineReason? reason,
  String? note,
}) {
  final declined = reason != null;
  return OrderHistoryEntry(
    id: 'order-1',
    status: status,
    vendorName: 'Spice Garden',
    totalKobo: 250000,
    note: null,
    deliveryLocationLabel: 'Hall 1',
    items: const [OrderHistoryItemLine(name: 'Jollof Rice', quantity: 1, priceKobo: 200000)],
    createdAt: DateTime(2026, 9, 25, 12, 0),
    cancelledAt: declined ? DateTime(2026, 9, 25, 12, 2) : null,
    paymentMethod: paymentMethod,
    declinedAt: declined ? DateTime(2026, 9, 25, 12, 2) : null,
    declineReason: reason,
    declineReasonNote: note,
  );
}

/// Replays [responses] in order for `GET /orders/:id`, repeating the last
/// one — counts every fetch so tests can prove polling stops.
class _ScriptedOrdersRepository extends OrdersRepository {
  _ScriptedOrdersRepository(this.responses);
  final List<OrderHistoryEntry> responses;
  int fetches = 0;

  @override
  Future<OrderHistoryEntry> fetchOrderDetail({required String orderId, required String token}) async {
    final response = responses[fetches.clamp(0, responses.length - 1)];
    fetches++;
    return response;
  }

  @override
  Future<OrderHistoryPage> fetchOrderHistory({int page = 1, int limit = 20, required String token}) async =>
      OrderHistoryPage(items: [responses.last], total: 1, page: page, limit: limit);
}

class _CountingWallet extends WalletBalanceController {
  static int builds = 0;
  @override
  Future<int> build() async {
    builds++;
    return 500000;
  }
}

Widget _trackingHarness(_ScriptedOrdersRepository repo) {
  final router = GoRouter(
    initialLocation: AppRoutes.orderTracking,
    routes: [
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const OrderTrackingScreen()),
      GoRoute(path: AppRoutes.studentOrders, builder: (_, _) => const Text('MY_ORDERS')),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
      ordersRepositoryProvider.overrideWithValue(repo),
      walletBalanceProvider.overrideWith(_CountingWallet.new),
      orderStatusPollIntervalProvider.overrideWithValue(const Duration(milliseconds: 100)),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

Future<void> _placeOrder(WidgetTester tester) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)));
  container
      .read(orderTrackingProvider.notifier)
      .placeOrder(
        orderId: 'order-1',
        orderItems: const ['1 × Jollof Rice'],
        total: 2500,
        eateryName: 'Spice Garden',
        deliveryLocationLabel: 'Hall 1',
      );
  await tester.pump();
}

void main() {
  setUp(() => _CountingWallet.builds = 0);

  group('Task 61: the student sees a real restaurant decline on the tracking screen', () {
    testWidgets('wallet order: the stated reason, and confirmation the full refund is on its way', (tester) async {
      final repo = _ScriptedOrdersRepository([
        _order(status: 'placed'),
        _order(status: 'cancelled', reason: OrderDeclineReason.outOfStock),
      ]);
      await tester.pumpWidget(_trackingHarness(repo));
      await tester.pump();
      await _placeOrder(tester);

      // First tick: still placed — the live tracker stays up.
      await tester.pump(const Duration(milliseconds: 110));
      expect(find.text('Order declined'), findsNothing);

      // Second tick: the restaurant declined it.
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(find.text('Order declined'), findsOneWidget);
      expect(find.text("Spice Garden couldn't take your order."), findsOneWidget);
      expect(find.text('Reason: Out of stock'), findsOneWidget);
      expect(find.text('Your ₦2500 refund is on its way back to your RUN IT wallet.'), findsOneWidget);
      // The app-level notification carries the same honest message.
      expect(
        find.text(
          'Spice Garden declined your order: Out of stock. Your ₦2500 refund is on its way back to your RUN IT wallet.',
        ),
        findsOneWidget,
      );
      // The wallet balance is re-fetched so the refund actually shows.
      expect(_CountingWallet.builds, greaterThanOrEqualTo(1));

      // Polling stops once the decline is known.
      final fetchesAtDecline = repo.fetches;
      await tester.pump(const Duration(milliseconds: 500));
      expect(repo.fetches, fetchesAtDecline);

      await tester.tap(find.text('Back to My Orders'));
      await tester.pumpAndSettle();
      expect(find.text('MY_ORDERS'), findsOneWidget);
    });

    testWidgets("'Other' shows the restaurant's own words", (tester) async {
      final repo = _ScriptedOrdersRepository([
        _order(status: 'cancelled', reason: OrderDeclineReason.other, note: 'Gas ran out'),
      ]);
      await tester.pumpWidget(_trackingHarness(repo));
      await tester.pump();
      await _placeOrder(tester);
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(find.text('Reason: Gas ran out'), findsOneWidget);
      ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)))
          .read(orderTrackingProvider.notifier)
          .resetOrder();
      await tester.pump();
    });

    testWidgets('Pay on Delivery order: says nothing was charged, never claims a refund', (tester) async {
      final repo = _ScriptedOrdersRepository([
        _order(status: 'cancelled', paymentMethod: 'pay_on_delivery', reason: OrderDeclineReason.tooBusy),
      ]);
      await tester.pumpWidget(_trackingHarness(repo));
      await tester.pump();
      await _placeOrder(tester);
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump();

      expect(find.text('Order declined'), findsOneWidget);
      expect(find.text("You haven't been charged for this order."), findsOneWidget);
      expect(find.textContaining('refund'), findsNothing);
      expect(_CountingWallet.builds, 0);
      ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)))
          .read(orderTrackingProvider.notifier)
          .resetOrder();
      await tester.pump();
    });

    testWidgets('once the restaurant accepts, polling stops for good', (tester) async {
      final repo = _ScriptedOrdersRepository([_order(status: 'preparing')]);
      await tester.pumpWidget(_trackingHarness(repo));
      await tester.pump();
      await _placeOrder(tester);

      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 600));

      expect(repo.fetches, 1);
      expect(find.text('Order declined'), findsNothing);
      ProviderScope.containerOf(tester.element(find.byType(OrderTrackingScreen)))
          .read(orderTrackingProvider.notifier)
          .resetOrder();
      await tester.pump();
    });
  });

  testWidgets('Task 61: a declined order in history and detail says who declined it, why, and the refund', (
    tester,
  ) async {
    final declined = _order(status: 'cancelled', reason: OrderDeclineReason.kitchenClosed);
    final router = GoRouter(
      initialLocation: AppRoutes.studentOrders,
      routes: [
        GoRoute(path: AppRoutes.studentOrders, builder: (_, _) => const MyOrdersScreen()),
        GoRoute(
          path: AppRoutes.orderDetail,
          builder: (_, state) => OrderDetailScreen(orderId: state.extra as String),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
          ordersRepositoryProvider.overrideWithValue(_ScriptedOrdersRepository([declined])),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Cancelled'));
    await tester.pump();
    expect(find.textContaining('Declined by restaurant'), findsOneWidget);

    await tester.tap(find.text('Spice Garden'));
    await tester.pumpAndSettle();

    expect(find.text('Declined by Spice Garden'), findsOneWidget);
    expect(find.text('Reason: Kitchen closed'), findsOneWidget);
    expect(find.text('₦2500 refunded'), findsOneWidget);
  });
}
