import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/order_detail_screen.dart';

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

final _deliveredOrder = OrderHistoryEntry(
  id: 'order-past-1',
  status: 'delivered',
  vendorName: 'Tantalizers',
  totalKobo: 320000,
  note: 'Leave at the gate, please',
  deliveryLocationLabel: 'Hostel B',
  items: const [
    OrderHistoryItemLine(name: 'Jollof Rice', quantity: 2, priceKobo: 150000),
    OrderHistoryItemLine(name: 'Coke', quantity: 1, priceKobo: 20000),
  ],
  createdAt: DateTime(2026, 1, 5, 12, 0),
  acceptedAt: DateTime(2026, 1, 5, 12, 5),
  pickedUpAt: DateTime(2026, 1, 5, 12, 20),
  deliveredAt: DateTime(2026, 1, 5, 12, 35),
);

final _cancelledOrder = OrderHistoryEntry(
  id: 'order-cancelled-1',
  status: 'cancelled',
  vendorName: 'FoodCo',
  totalKobo: 280000,
  note: null,
  deliveryLocationLabel: 'Hostel A',
  items: const [OrderHistoryItemLine(name: 'Burger', quantity: 1, priceKobo: 280000)],
  createdAt: DateTime(2026, 1, 6, 9, 0),
  cancelledAt: DateTime(2026, 1, 6, 9, 5),
);

class _FakeOrdersRepository extends OrdersRepository {
  const _FakeOrdersRepository();

  @override
  Future<OrderHistoryPage> fetchOrderHistory({
    int page = 1,
    int limit = 20,
    required String token,
  }) async => OrderHistoryPage(
    items: [_deliveredOrder, _cancelledOrder],
    total: 2,
    page: page,
    limit: limit,
  );

  @override
  Future<OrderHistoryEntry> fetchOrderDetail({
    required String orderId,
    required String token,
  }) async {
    return [_deliveredOrder, _cancelledOrder].firstWhere((o) => o.id == orderId);
  }
}

Widget _harness() {
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
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
      ordersRepositoryProvider.overrideWithValue(const _FakeOrdersRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets(
    'Task 46: the Past tab shows a real delivered order and its detail view shows the real timestamped lifecycle',
    (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Past'));
      await tester.pump();
      expect(find.text('Tantalizers'), findsOneWidget);
      expect(find.text('₦3200'), findsOneWidget);

      await tester.tap(find.text('Tantalizers'));
      await tester.pumpAndSettle();

      expect(find.text('Order details'), findsOneWidget);
      // The full real lifecycle, each stage carrying its own real time —
      // not a generic "delivered" label with no history.
      expect(find.textContaining('Placed'), findsOneWidget);
      expect(find.textContaining('Jan 5, 12:00 PM'), findsOneWidget);
      expect(find.textContaining('Accepted'), findsOneWidget);
      expect(find.textContaining('Jan 5, 12:05 PM'), findsOneWidget);
      expect(find.textContaining('Picked Up'), findsOneWidget);
      expect(find.textContaining('Jan 5, 12:20 PM'), findsOneWidget);
      expect(find.textContaining('Delivered'), findsOneWidget);
      expect(find.textContaining('Jan 5, 12:35 PM'), findsOneWidget);
      // The order-level note (Task 45) and delivery location both surface
      // on the real detail view.
      expect(find.text('Leave at the gate, please'), findsOneWidget);
      expect(find.text('Hostel B'), findsOneWidget);
    },
  );

  testWidgets(
    'Task 46: the Cancelled tab shows a real cancelled order and its detail view shows the refund, not a stepper',
    (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Cancelled'));
      await tester.pump();
      expect(find.text('FoodCo'), findsOneWidget);

      await tester.tap(find.text('FoodCo'));
      await tester.pumpAndSettle();

      expect(find.text('Order cancelled'), findsOneWidget);
      expect(find.textContaining('Jan 6, 9:05 AM'), findsOneWidget);
      expect(find.text('₦2800 refunded'), findsOneWidget);
      // No lifecycle stepper for a cancelled order — it never reached
      // "delivered" and shouldn't be shown as if it were mid-progress.
      expect(find.textContaining('Picked Up'), findsNothing);
    },
  );

  testWidgets(
    'the Full order history "coming soon" placeholder is gone — this is now a real feature',
    (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.access_time), findsNothing);
      expect(find.textContaining('coming soon'), findsNothing);
    },
  );
}
