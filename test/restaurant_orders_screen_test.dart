import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/vendor/presentation/restaurant_orders_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _restaurantSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'restaurant-1',
    name: 'Mama Kemi',
    contact: 'kemi@campus.edu',
    accountType: AccountType.restaurant,
    campusId: 'ui',
  ),
);

RestaurantOrder _order({
  required String id,
  required RestaurantOrderStatus status,
  String? notes,
}) => RestaurantOrder(
  id: id,
  status: status,
  pickupCode: '4821',
  totalKobo: 350000,
  deliveryLocationLabel: 'Hostel B',
  createdAt: DateTime(2026, 1, 1),
  items: [
    RestaurantOrderItem(id: '$id-item-1', name: 'Jollof Rice', quantity: 2, priceKobo: 150000, notes: notes),
  ],
);

/// A minimal in-memory stand-in for the real backend's order-status
/// transitions — same "subclass the repository, keep mutable state"
/// convention as this codebase's other repository fakes.
class _FakeVendorsRepository extends VendorsRepository {
  _FakeVendorsRepository(this.orders);
  final List<RestaurantOrder> orders;
  bool failNextAdvance = false;

  @override
  Future<VendorOrdersPage> fetchOrders({
    RestaurantOrderStatus? status,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    final filtered = status == null ? orders : orders.where((o) => o.status == status).toList();
    return VendorOrdersPage(items: List.of(filtered), total: filtered.length, page: page, limit: limit);
  }

  @override
  Future<void> advanceOrderStatus({
    required String orderId,
    required RestaurantOrderStatus status,
    required String token,
  }) async {
    if (failNextAdvance) {
      throw const ApiException(409, 'Cannot move order to that status right now.');
    }
    final index = orders.indexWhere((o) => o.id == orderId);
    final current = orders[index];
    orders[index] = RestaurantOrder(
      id: current.id,
      status: status,
      pickupCode: current.pickupCode,
      totalKobo: current.totalKobo,
      deliveryLocationLabel: current.deliveryLocationLabel,
      createdAt: current.createdAt,
      items: current.items,
    );
  }
}

Widget _harness(_FakeVendorsRepository repo) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_restaurantSession())),
      vendorsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      home: const RestaurantOrdersScreen(),
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  testWidgets('shows items, quantities, and the student note — the field a kitchen card must not forget', (
    tester,
  ) async {
    final repo = _FakeVendorsRepository([
      _order(id: 'order-1', status: RestaurantOrderStatus.placed, notes: 'No onions please'),
    ]);
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    // A second, timed pump so the resolved fetch replaces the loading
    // skeleton — its shimmer repeats forever by design, so a lone
    // zero-duration pump can leave its timer pending past the end of the
    // test.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('2×'), findsOneWidget);
    expect(find.text('Jollof Rice'), findsOneWidget);
    expect(find.text('"No onions please"'), findsOneWidget);
    expect(find.text('Start Preparing'), findsOneWidget);
  });

  testWidgets('tapping "Start Preparing" advances the order and reflects the confirmed new status, not optimistically', (
    tester,
  ) async {
    final repo = _FakeVendorsRepository([_order(id: 'order-1', status: RestaurantOrderStatus.placed)]);
    await tester.pumpWidget(_harness(repo));
    await tester.pump();

    expect(find.text('New'), findsOneWidget);
    await tester.tap(find.text('Start Preparing'));
    // The button shows its own loading state while the call is in flight —
    // not an instant local flip.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(repo.orders.single.status, RestaurantOrderStatus.preparing);
    expect(find.text('Preparing'), findsOneWidget);
    expect(find.text('Mark Ready for Pickup'), findsOneWidget);
    expect(find.text('Start Preparing'), findsNothing);
  });

  testWidgets('shows the pickup code once ready for pickup', (tester) async {
    final repo = _FakeVendorsRepository([_order(id: 'order-1', status: RestaurantOrderStatus.readyForPickup)]);
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('4821'), findsOneWidget);
    // No forward action left for the vendor once it's ready — that's the
    // runner's job now (Task 11).
    expect(find.text('Mark Ready for Pickup'), findsNothing);
  });

  testWidgets('a rejected transition shows the real backend error and leaves the status unchanged', (tester) async {
    final repo = _FakeVendorsRepository([_order(id: 'order-1', status: RestaurantOrderStatus.placed)])
      ..failNextAdvance = true;
    await tester.pumpWidget(_harness(repo));
    await tester.pump();

    await tester.tap(find.text('Start Preparing'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Cannot move order to that status right now.'), findsOneWidget);
    expect(repo.orders.single.status, RestaurantOrderStatus.placed);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Start Preparing'), findsOneWidget);
  });
}
