import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:run_it/core/cache/cached_fetch.dart';
import 'package:run_it/core/cache/local_cache.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/connectivity.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/order_history_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';
import 'package:run_it/features/wallet/data/wallet_repository.dart';
import 'package:run_it/features/wallet/domain/wallet_models.dart';
import 'package:run_it/features/wallet/presentation/wallet_screen.dart';

const _userId = 'student-1';
// Today at 9:41 — "Last updated" shows just the time for a copy saved
// today, so a fixed date would start failing the day after it was written.
final _savedAt = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 9, 41);
}();

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    user: const UserProfile(
      id: _userId,
      name: 'Ayanfe O.',
      contact: 'a@student.ui.edu.ng',
      accountType: AccountType.student,
      campusId: 'ui',
    ),
  );

  void signOut({required bool expired}) {
    this.expired = expired;
    state = null;
  }
}

/// The backend, which can be offline, slow ([gate]) or answering.
class _Backend {
  bool online = true;
  Completer<void>? gate;
  var vendorNames = ['Golden Crust Bakery'];
  var balanceKobo = 355500;
  var orderStatus = 'delivered';
  final calls = <String>[];

  Future<void> answer(String call) async {
    calls.add(call);
    if (gate != null) await gate!.future;
    if (!online) throw const SocketException('offline');
  }
}

class _Vendors extends VendorsRepository {
  _Vendors(this.backend);
  final _Backend backend;

  @override
  Future<VendorsPage> listVendors({
    String? category,
    String? search,
    String? sort,
    double? minRating,
    int? maxPriceKobo,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    await backend.answer('vendors');
    final items = [
      for (final (i, name) in backend.vendorNames.indexed)
        MyVendorProfile(id: 'v$i', businessName: name, category: 'Bakery & Pastries'),
    ];
    return VendorsPage(items: items, total: items.length, page: page, limit: limit);
  }

  @override
  Future<List<VendorCategoryOption>> fetchCategories() async {
    await backend.answer('categories');
    return const [VendorCategoryOption(slug: 'bakery-pastries', label: 'Bakery & Pastries')];
  }

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async {
    await backend.answer('menu');
    return const VendorWithMenu(
      vendor: MyVendorProfile(id: 'v0', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries'),
      items: [
        VendorMenuItem(
          id: 'pie',
          name: 'Chicken Pie',
          priceKobo: 90000,
          category: 'Pastries',
          isAvailable: true,
          isMainMeal: false,
        ),
      ],
    );
  }
}

class _Orders extends OrdersRepository {
  _Orders(this.backend);
  final _Backend backend;

  @override
  Future<OrderHistoryPage> fetchOrderHistory({int page = 1, int limit = 20, required String token}) async {
    await backend.answer('orders');
    return OrderHistoryPage(items: [_order(backend.orderStatus)], total: 1, page: page, limit: limit);
  }
}

class _Wallet extends WalletRepository {
  _Wallet(this.backend);
  final _Backend backend;

  @override
  Future<int> getBalance({required String userId, required String token}) async {
    await backend.answer('wallet');
    return backend.balanceKobo ~/ 100;
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

OrderHistoryEntry _order(String status) => OrderHistoryEntry(
  id: 'order-1',
  status: status,
  vendorName: 'Golden Crust Bakery',
  totalKobo: 144500,
  note: null,
  deliveryLocationLabel: null,
  items: const [OrderHistoryItemLine(name: 'Chicken Pie', quantity: 1, priceKobo: 90000)],
  createdAt: DateTime.utc(2026, 10, 1, 8),
  deliveredAt: status == 'delivered' ? DateTime.utc(2026, 10, 1, 8, 30) : null,
);

/// What a previous session saved: one restaurant, its menu, one delivered
/// order and a ₦3,555 balance.
MemoryLocalCache _previousSession() {
  final cache = MemoryLocalCache(clock: () => _savedAt);
  cache
    ..write(CacheKeys.vendors(_userId), [
      const MyVendorProfile(id: 'v0', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries').toJson(),
    ])
    ..write(CacheKeys.categories, [const VendorCategoryOption(slug: 'bakery-pastries', label: 'Bakery & Pastries').toJson()])
    ..write(CacheKeys.orders(_userId), [_order('delivered').toJson()])
    ..write(CacheKeys.wallet(_userId), 3555);
  return cache;
}

List<Override> _overrides(_Backend backend, LocalCache cache) => [
  authControllerProvider.overrideWith(_FakeAuthController.new),
  localCacheProvider.overrideWithValue(cache),
  vendorsRepositoryProvider.overrideWithValue(_Vendors(backend)),
  ordersRepositoryProvider.overrideWithValue(_Orders(backend)),
  walletRepositoryProvider.overrideWithValue(_Wallet(backend)),
];

Future<void> _pumpHome(WidgetTester tester, _Backend backend, LocalCache cache) async {
  // google_fonts can't load in tests; the promo card's fallback font
  // overflows there only (see home_search_test).
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    final context = details.informationCollector?.call().map((node) => node.toStringDeep()).join() ?? '';
    if (!(details.exceptionAsString().contains('overflowed') && context.contains('_PromoCard'))) {
      reportError?.call(details);
    }
  };
  addTearDown(() => FlutterError.onError = reportError);
  tester.view.physicalSize = const Size(2400, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(overrides: _overrides(backend, cache), child: const MaterialApp(home: HomeScreen())),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Home, opened with no connection', () {
    testWidgets('a returning user sees the saved restaurants, marked "Last updated", not an error', (tester) async {
      final backend = _Backend()..online = false;
      await _pumpHome(tester, backend, _previousSession());

      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Last updated 9:41 AM'), findsOneWidget);
      expect(find.textContaining("Couldn't load vendors"), findsNothing);
    });

    testWidgets('first-ever open with no connection still shows the existing error state', (tester) async {
      final backend = _Backend()..online = false;
      await _pumpHome(tester, backend, MemoryLocalCache());

      expect(find.textContaining("Couldn't load vendors"), findsOneWidget);
      expect(find.textContaining('Last updated'), findsNothing);
    });
  });

  group('Cache then refresh', () {
    testWidgets('the saved copy shows at once — never waiting on the network — then updates silently', (
      tester,
    ) async {
      final backend = _Backend()
        ..gate = Completer<void>()
        ..vendorNames = ['Golden Crust Bakery', 'Grillhouse 7'];
      await _pumpHome(tester, backend, _previousSession());

      // The network hasn't answered: the saved list is already up.
      expect(backend.calls, contains('vendors'));
      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Grillhouse 7'), findsNothing);
      expect(find.text('Last updated 9:41 AM'), findsOneWidget);

      backend.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Grillhouse 7'), findsOneWidget);
      expect(find.textContaining('Last updated'), findsNothing);      await tester.pump(const Duration(seconds: 1)); // card fade-ins
    });

    test('a live load is saved for next time', () async {
      final backend = _Backend();
      final cache = MemoryLocalCache();
      final container = ProviderContainer(overrides: _overrides(backend, cache));
      addTearDown(container.dispose);

      await container.read(campusEateriesProvider.future);
      await container.read(orderHistoryProvider.future);
      await container.read(walletBalanceProvider.future);
      await container.read(vendorCategoriesProvider.future);

      expect(cache.read(CacheKeys.vendors(_userId))!.json, [
        containsPair('businessName', 'Golden Crust Bakery'),
      ]);
      expect(cache.read(CacheKeys.orders(_userId))!.json, [containsPair('id', 'order-1')]);
      expect(cache.read(CacheKeys.wallet(_userId))!.json, 3555);
      expect(cache.read(CacheKeys.categories), isNotNull);
    });

    test('menus, order history and the wallet balance all come back from the saved copy offline', () async {
      final backend = _Backend();
      final cache = MemoryLocalCache(clock: () => _savedAt);
      // One online session saves them...
      final online = ProviderContainer(
        overrides: [..._overrides(backend, cache), selectedVendorIdProvider.overrideWith((ref) => 'v0')],
      );
      await online.read(selectedVendorWithMenuProvider.future);
      await online.read(orderHistoryProvider.future);
      await online.read(walletBalanceProvider.future);
      online.dispose();

      // ...the next opens offline.
      backend.online = false;
      final offline = ProviderContainer(
        overrides: [..._overrides(backend, cache), selectedVendorIdProvider.overrideWith((ref) => 'v0')],
      );
      addTearDown(offline.dispose);

      final menu = await offline.read(selectedVendorWithMenuProvider.future);
      expect(menu!.items.single.name, 'Chicken Pie');
      expect((await offline.read(orderHistoryProvider.future)).single.vendorName, 'Golden Crust Bakery');
      expect(await offline.read(walletBalanceProvider.future), 3555);
      await _settle();
      expect(offline.read(staleCacheProvider).keys, {
        CacheKeys.menu('v0'),
        CacheKeys.orders(_userId),
        CacheKeys.wallet(_userId),
      });
    });

    test('a real backend answer is never papered over with the saved copy', () async {
      final backend = _Backend();
      final cache = _previousSession();
      final container = ProviderContainer(
        overrides: [
          ..._overrides(backend, cache),
          walletRepositoryProvider.overrideWithValue(_RefusingWallet()),
        ],
      );
      addTearDown(container.dispose);
      container.read(cacheSessionProvider).forceNetwork(CacheKeys.wallet(_userId));

      await expectLater(container.read(walletBalanceProvider.future), throwsA(isA<ApiException>()));
    });

    test('an explicit refresh (checkout, top-up polling) asks the network, never just the saved copy', () async {
      final backend = _Backend()..balanceKobo = 900000;
      final container = ProviderContainer(overrides: _overrides(backend, _previousSession()));
      addTearDown(container.dispose);

      // First read is the saved copy...
      expect(await container.read(walletBalanceProvider.future), 3555);
      // ...but refresh() waits for the real balance.
      backend.gate = Completer<void>();
      final refreshed = container.read(walletBalanceProvider.notifier).refresh();
      backend.gate!.complete();
      expect(await refreshed, 9000);
    });
  });

  group('Offline banner and reconnect', () {
    test('coming back online refreshes every saved copy — screens not open included', () async {
      final backend = _Backend()..online = false;
      final cache = _previousSession();
      final connectivity = _FakeConnectivity(false);
      final container = ProviderContainer(
        overrides: [..._overrides(backend, cache), connectivitySourceProvider.overrideWithValue(connectivity)],
      );
      addTearDown(container.dispose);
      container
        ..read(reconnectRefresherProvider)
        ..read(isOnlineProvider);
      await _settle();

      // Nothing is open. Things changed while the phone was offline.
      backend
        ..online = true
        ..balanceKobo = 120000
        ..orderStatus = 'cancelled'
        ..vendorNames = ['Golden Crust Bakery', 'Grillhouse 7'];
      connectivity.set(true);
      await _settle();

      expect(cache.read(CacheKeys.wallet(_userId))!.json, 1200);
      expect(cache.read(CacheKeys.orders(_userId))!.json, [containsPair('status', 'cancelled')]);
      expect((cache.read(CacheKeys.vendors(_userId))!.json! as List).length, 2);
      // And opening them now shows the fresh data, not the old saved copy.
      expect(await container.read(walletBalanceProvider.future), 1200);
      expect((await container.read(orderHistoryProvider.future)).single.status, 'cancelled');
      await _settle();
      expect(container.read(staleCacheProvider), isEmpty);
    });

    testWidgets('the open screen updates when the connection returns, and its "Last updated" goes', (
      tester,
    ) async {
      final backend = _Backend()..online = false;
      final connectivity = _FakeConnectivity(false);
      final reportError = FlutterError.onError;
      FlutterError.onError = (details) {
        final context = details.informationCollector?.call().map((node) => node.toStringDeep()).join() ?? '';
        if (!(details.exceptionAsString().contains('overflowed') && context.contains('_PromoCard'))) {
          reportError?.call(details);
        }
      };
      addTearDown(() => FlutterError.onError = reportError);
      tester.view.physicalSize = const Size(2400, 4800);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._overrides(backend, _previousSession()),
            connectivitySourceProvider.overrideWithValue(connectivity),
          ],
          child: const MaterialApp(home: OfflineBanner(child: _WithRefresher(child: HomeScreen()))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The banner sits over the saved copy, so it's clear why it may be old.
      expect(find.textContaining('You’re offline'), findsOneWidget);
      expect(find.text('Last updated 9:41 AM'), findsOneWidget);

      backend
        ..online = true
        ..vendorNames = ['Golden Crust Bakery', 'Grillhouse 7'];
      connectivity.set(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('You’re offline'), findsNothing);
      expect(find.text('Grillhouse 7'), findsOneWidget);
      expect(find.textContaining('Last updated'), findsNothing);      await tester.pump(const Duration(seconds: 1)); // card fade-ins
    });
  });

  group('Whose data', () {
    test('"Log out" wipes the saved copy; a session merely expiring keeps it', () async {
      final cache = _previousSession();
      final container = ProviderContainer(overrides: _overrides(_Backend(), cache));
      addTearDown(container.dispose);
      container.read(cacheLifecycleProvider);
      final auth = container.read(authControllerProvider.notifier) as _FakeAuthController;

      auth.signOut(expired: true);
      await _settle();
      expect(cache.keys, isNotEmpty);

      container.invalidate(authControllerProvider);
      container.read(authControllerProvider);
      (container.read(authControllerProvider.notifier) as _FakeAuthController).signOut(expired: false);
      await _settle();
      expect(cache.keys, isEmpty);
    });

    test('order history and balance are saved per user', () {
      expect(CacheKeys.orders('a'), isNot(CacheKeys.orders('b')));
      expect(CacheKeys.wallet('a'), isNot(CacheKeys.wallet('b')));
      expect(CacheKeys.vendors('a'), isNot(CacheKeys.vendors('b')));
    });
  });

  test('the Hive store round-trips what it saves, with when it was saved', () async {
    final dir = await Directory.systemTemp.createTemp('run_it_cache_test');
    addTearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });
    Hive.init(dir.path);
    final cache = await HiveLocalCache.open();

    final before = DateTime.now();
    await cache.write('k', {'balance': 3555, 'items': ['Chicken Pie']});
    final entry = cache.read('k')!;

    expect(entry.json, {'balance': 3555, 'items': ['Chicken Pie']});
    expect(entry.savedAt.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
    expect(cache.read('missing'), isNull);
    expect(cache.keys, ['k']);
  });

  testWidgets('Wallet offline: the saved balance, marked as such — and transactions say they could not load', (
    tester,
  ) async {
    final backend = _Backend()..online = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(backend, _previousSession()),
          walletTransactionsProvider.overrideWith(_OfflineTransactions.new),
        ],
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('₦3,555.00'), findsOneWidget);
    expect(find.text('Last updated 9:41 AM'), findsOneWidget);
    expect(find.textContaining("Couldn't load your transactions"), findsOneWidget);
    expect(find.text('No transactions yet.'), findsNothing);
  });

  testWidgets('My Orders shows the saved history offline, marked as such', (tester) async {
    final backend = _Backend()..online = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(backend, _previousSession()),
        child: const MaterialApp(home: MyOrdersScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Last updated 9:41 AM'), findsOneWidget);
    await tester.tap(find.text('Past'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Golden Crust Bakery'), findsWidgets);
  });
}

class _OfflineTransactions extends WalletTransactionsController {
  @override
  Future<List<WalletTransaction>> build() async => throw const SocketException('offline');
}

class _RefusingWallet extends WalletRepository {
  @override
  Future<int> getBalance({required String userId, required String token}) async =>
      throw const ApiException(403, 'Not allowed');
}

/// Stands in for the app root watching the reconnect refresher.
class _WithRefresher extends ConsumerWidget {
  const _WithRefresher({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(reconnectRefresherProvider);
    return child;
  }
}
