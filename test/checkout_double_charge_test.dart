import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/connectivity.dart';
import 'package:run_it/core/network/demo_identity_service.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/active_order_restorer.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
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
}

class _SeededBasket extends BasketNotifier {
  @override
  Basket build() => const Basket(eateryId: 'golden', items: [BasketItem(menuItemId: 'pie', quantity: 1)]);
}

class _Wallet extends WalletBalanceController {
  @override
  Future<int> build() async => 50000;
}

class _Identity extends DemoIdentityService {
  const _Identity();
  @override
  Future<String> ensureRestaurantUserId() async => 'restaurant-1';
}

class _Vendors extends VendorsRepository {
  const _Vendors();
  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async => const VendorWithMenu(
    vendor: MyVendorProfile(id: 'golden', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries', userId: 'restaurant-1'),
    items: [
      VendorMenuItem(
        id: 'pie',
        name: 'Chicken Pie',
        description: 'Flaky pastry.',
        priceKobo: 90000,
        category: 'Pastries',
        isAvailable: true,
        isMainMeal: false,
      ),
    ],
  );
}

/// The backend, in memory: a hold charges the wallet and creates the order
/// exactly once per order id (a second hold for the same id is a 409 before
/// any money moves — OrderEscrowService.hold's real duplicate check).
class _Backend {
  final charges = <String>[];
  final holdAttempts = <String>[];

  bool get hasOrder => charges.isNotEmpty;

  OrderHistoryEntry order(String id, {String status = 'placed', String? runnerName}) => OrderHistoryEntry.fromJson({
    'id': id,
    'status': status,
    'vendorName': 'Golden Crust Bakery',
    'totalAmount': 144500,
    'deliveryLocationLabel': 'University of Ibadan · Drop-off point',
    'items': [
      {'name': 'Chicken Pie', 'quantity': 1, 'priceKobo': 90000},
    ],
    'createdAt': '2026-09-30T20:15:24.000Z',
    'runnerName': runnerName,
  });
}

enum _HoldScript { chargeThenTimeout, timeoutWithoutCharge, normal }

class _Escrow extends EscrowRepository {
  _Escrow(this.backend, this.script);
  final _Backend backend;
  final List<_HoldScript> script;

  @override
  Future<void> hold({
    required String orderId,
    required String studentUserId,
    required String restaurantUserId,
    String? runnerUserId,
    required int grossAmountKobo,
    required String token,
    String? vendorId,
    List<EscrowOrderItem>? items,
    int? deliveryFeeKobo,
    int? serviceFeeKobo,
    String? deliveryLocationLabel,
    String? note,
    String? paymentMethod,
    String? orderType,
  }) async {
    backend.holdAttempts.add(orderId);
    if (backend.charges.contains(orderId)) {
      throw ApiException(409, 'Escrow already exists for order $orderId (status: held)');
    }
    final step = script.isEmpty ? _HoldScript.normal : script.removeAt(0);
    if (step == _HoldScript.timeoutWithoutCharge) throw TimeoutException('request never arrived');
    backend.charges.add(orderId); // the wallet is debited, the order exists
    if (step == _HoldScript.chargeThenTimeout) throw TimeoutException('response lost');
  }
}

class _Orders extends OrdersRepository {
  _Orders(this.backend, {this.unreachableChecks = 0});
  final _Backend backend;
  int unreachableChecks;

  @override
  Future<OrderHistoryEntry> fetchOrderDetail({required String orderId, required String token}) async {
    if (unreachableChecks > 0) {
      unreachableChecks--;
      throw TimeoutException('still offline');
    }
    if (!backend.charges.contains(orderId)) throw const ApiException(404, 'Order not found');
    return backend.order(orderId);
  }

  @override
  Future<String?> fetchDeliveryPin({required String orderId, required String token}) async => '4821';
}

Future<void> _pumpCheckout(WidgetTester tester, _Backend backend, _Escrow escrow, _Orders orders) async {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final router = GoRouter(
    initialLocation: AppRoutes.checkout,
    routes: [
      GoRoute(path: AppRoutes.checkout, builder: (_, _) => const CheckoutScreen()),
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const Scaffold(body: Text('TRACKING'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        basketProvider.overrideWith(_SeededBasket.new),
        walletBalanceProvider.overrideWith(_Wallet.new),
        demoIdentityServiceProvider.overrideWithValue(const _Identity()),
        vendorsRepositoryProvider.overrideWithValue(const _Vendors()),
        selectedVendorIdProvider.overrideWith((ref) => 'golden'),
        escrowRepositoryProvider.overrideWithValue(escrow),
        ordersRepositoryProvider.overrideWithValue(orders),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

Future<void> _tapPlaceOrder(WidgetTester tester) async {
  await tester.tap(find.textContaining('Place order'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('Checkout never charges twice', () {
    testWidgets('charged, then the response is lost: the app confirms the order and carries on — one charge', (
      tester,
    ) async {
      final backend = _Backend();
      await _pumpCheckout(tester, backend, _Escrow(backend, [_HoldScript.chargeThenTimeout]), _Orders(backend));

      await _tapPlaceOrder(tester);

      expect(find.text('TRACKING'), findsOneWidget);
      expect(backend.charges, hasLength(1));
      expect(backend.holdAttempts, hasLength(1));
    });

    testWidgets('charged, response lost, and the check is offline too: honest message, and the retry reuses the '
        'same order id — the backend refuses a second hold, the app finds the order, still one charge', (tester) async {
      final backend = _Backend();
      final orders = _Orders(backend, unreachableChecks: 1);
      await _pumpCheckout(tester, backend, _Escrow(backend, [_HoldScript.chargeThenTimeout]), orders);

      await _tapPlaceOrder(tester);
      expect(find.text('TRACKING'), findsNothing);
      expect(find.textContaining("We couldn't confirm your order"), findsOneWidget);

      await _tapPlaceOrder(tester);

      expect(backend.holdAttempts, hasLength(2));
      expect(backend.holdAttempts.toSet(), hasLength(1)); // the same order id both times
      expect(backend.charges, hasLength(1));
      expect(find.text('TRACKING'), findsOneWidget);
    });

    testWidgets('the request never arrived: "couldn\'t reach the server", and the retry places it exactly once', (
      tester,
    ) async {
      final backend = _Backend();
      await _pumpCheckout(tester, backend, _Escrow(backend, [_HoldScript.timeoutWithoutCharge]), _Orders(backend));

      await _tapPlaceOrder(tester);
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      expect(backend.charges, isEmpty);

      await _tapPlaceOrder(tester);
      expect(backend.charges, hasLength(1));
      expect(backend.holdAttempts.toSet(), hasLength(1));
      expect(find.text('TRACKING'), findsOneWidget);
    });
  });

  group('An in-progress order is never lost', () {
    OrdersRepository historyWith(_Backend backend, OrderHistoryEntry order) => _HistoryOrders(backend, [order]);

    test('after an app restart, the in-progress order is picked back up — runner, stage and all', () async {
      final backend = _Backend()..charges.add('order-1');
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
          ordersRepositoryProvider.overrideWithValue(
            historyWith(backend, backend.order('order-1', status: 'preparing', runnerName: 'Test R.')),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeOrderRestorerProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final session = container.read(orderTrackingProvider);
      expect(session.orderId, 'order-1');
      expect(session.stage, OrderStage.runnerAssigned);
      expect(session.runnerName, 'Test R.');
      expect(session.deliveryPin, '4821');
      expect(session.orderItems, ['1 × Chicken Pie']);
      expect(session.total, 1445);
    });

    test('a restart while the backend is unreachable keeps trying until the order is back', () async {
      final backend = _Backend()..charges.add('order-1');
      final orders = _FlakyHistoryOrders(backend, [backend.order('order-1', status: 'preparing', runnerName: 'Test R.')])
        ..failuresLeft = 2;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
          ordersRepositoryProvider.overrideWithValue(orders),
          restoreRetryDelaysProvider.overrideWithValue(const [Duration.zero, Duration.zero, Duration.zero]),
        ],
      );
      addTearDown(container.dispose);

      container.read(activeOrderRestorerProvider);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(orders.historyCalls, 3);
      expect(container.read(orderTrackingProvider).orderId, 'order-1');
      expect(container.read(orderTrackingProvider).runnerName, 'Test R.');
    });

    test('out of retries at sign-in, coming back online still restores the order', () async {
      final backend = _Backend()..charges.add('order-1');
      final orders = _FlakyHistoryOrders(backend, [backend.order('order-1', status: 'preparing', runnerName: 'Test R.')])
        ..failuresLeft = 99;
      final connectivity = _FakeConnectivity(false);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
          ordersRepositoryProvider.overrideWithValue(orders),
          restoreRetryDelaysProvider.overrideWithValue(const [Duration.zero]),
          connectivitySourceProvider.overrideWithValue(connectivity),
        ],
      );
      addTearDown(container.dispose);
      container
        ..read(reconnectRefresherProvider)
        ..read(activeOrderRestorerProvider)
        ..read(isOnlineProvider);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(orders.historyCalls, 2);
      expect(container.read(orderTrackingProvider).orderId, isNull);

      orders.failuresLeft = 0;
      connectivity.set(true);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(container.read(orderTrackingProvider).orderId, 'order-1');
    });

    testWidgets('My Orders → Active lists an in-progress order from the server, with chat once a runner is on it', (
      tester,
    ) async {
      final backend = _Backend()..charges.add('order-1');
      final router = GoRouter(
        initialLocation: '/orders',
        routes: [
          GoRoute(path: '/orders', builder: (_, _) => const MyOrdersScreen()),
          GoRoute(path: AppRoutes.orderChat, builder: (_, state) => Text('CHAT ${state.extra}')),
          GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const Text('TRACKING')),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_FakeAuthController.new),
            ordersRepositoryProvider.overrideWithValue(
              historyWith(backend, backend.order('order-1', status: 'preparing', runnerName: 'Test R.')),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Active (1)'), findsOneWidget);
      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Test R.'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.chat_bubble_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('CHAT order-1'), findsOneWidget);
    });
  });
}

class _HistoryOrders extends _Orders {
  _HistoryOrders(super.backend, this.history);
  final List<OrderHistoryEntry> history;

  @override
  Future<OrderHistoryPage> fetchOrderHistory({int page = 1, int limit = 20, required String token}) async =>
      OrderHistoryPage(items: history, total: history.length, page: page, limit: limit);
}

/// Order history that fails with a dropped connection [failuresLeft] times.
class _FlakyHistoryOrders extends _HistoryOrders {
  _FlakyHistoryOrders(super.backend, super.history);
  var failuresLeft = 0;
  var historyCalls = 0;

  @override
  Future<OrderHistoryPage> fetchOrderHistory({int page = 1, int limit = 20, required String token}) async {
    historyCalls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const SocketException('unreachable');
    }
    return super.fetchOrderHistory(page: page, limit: limit, token: token);
  }
}

class _FakeConnectivity implements ConnectivitySource {
  _FakeConnectivity(this.online);
  bool online;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Future<bool> isOnline() async => online;
  @override
  Stream<bool> get onlineChanges => _changes.stream;
}
