import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/connectivity.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';

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

class _FakeAuthController extends AuthController {
  @override
  AuthSession? build() => AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    user: const UserProfile(
      id: 'student-1',
      name: 'Ayanfe O.',
      contact: 'a@student.ui.edu.ng',
      accountType: AccountType.student,
      campusId: 'ui',
    ),
  );
}

/// Fails every call until [online] — the menu while there's no network.
class _FlakyVendors extends VendorsRepository {
  bool online = false;
  var menuCalls = 0;
  var listCalls = 0;

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async {
    menuCalls++;
    if (!online) throw const SocketException('offline');
    return const VendorWithMenu(
      vendor: MyVendorProfile(id: 'golden', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries'),
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

  @override
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20, required String token}) async {
    listCalls++;
    if (!online) throw const SocketException('offline');
    return VendorsPage(items: const [], total: 0, page: page, limit: limit);
  }
}

void main() {
  group('offline banner', () {
    testWidgets('shows while there is no connection and goes away when it returns', (tester) async {
      final connectivity = _FakeConnectivity(false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectivitySourceProvider.overrideWithValue(connectivity)],
          child: const MaterialApp(home: OfflineBanner(child: Scaffold(body: Text('screen')))),
        ),
      );
      await tester.pump();
      expect(find.textContaining('You’re offline'), findsOneWidget);
      expect(find.text('screen'), findsOneWidget);

      connectivity.set(true);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('You’re offline'), findsNothing);
    });

    testWidgets('never flashes at startup before the first reading', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [connectivitySourceProvider.overrideWithValue(_FakeConnectivity(true))],
          child: const MaterialApp(home: OfflineBanner(child: Text('screen'))),
        ),
      );
      expect(find.textContaining('You’re offline'), findsNothing);
    });
  });

  test('coming back online reloads data that failed while offline', () async {
    final connectivity = _FakeConnectivity(false);
    final vendors = _FlakyVendors();
    final container = ProviderContainer(
      overrides: [
        connectivitySourceProvider.overrideWithValue(connectivity),
        authControllerProvider.overrideWith(_FakeAuthController.new),
        vendorsRepositoryProvider.overrideWithValue(vendors),
      ],
    );
    addTearDown(container.dispose);
    container
      ..read(reconnectRefresherProvider)
      ..read(isOnlineProvider);
    final sub = container.listen(campusEateriesProvider, (_, _) {});
    addTearDown(sub.close);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(campusEateriesProvider).hasError, isTrue);
    final callsWhileOffline = vendors.listCalls;

    vendors.online = true;
    connectivity.set(true);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(vendors.listCalls, greaterThan(callsWhileOffline));
    expect(container.read(campusEateriesProvider).hasValue, isTrue);
  });

  group('safe automatic retries', () {
    test('an idempotent POST retries a dropped connection, then succeeds', () async {
      var attempts = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          attempts++;
          if (attempts == 1) throw const SocketException('dropped');
          return http.Response('{"status":"picked_up"}', 200);
        }),
      );
      final result = await client.postIdempotent('/orders/o1/verify-pickup', body: const {'code': '1234'});
      expect(attempts, 2);
      expect(result, {'status': 'picked_up'});
    });

    test('a real backend answer is never retried (a wrong code stays one attempt)', () async {
      var attempts = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          attempts++;
          return http.Response('{"message":"This isn\'t the order you accepted."}', 400);
        }),
      );
      await expectLater(client.postIdempotent('/orders/o1/verify-pickup'), throwsA(isA<ApiException>()));
      expect(attempts, 1);
    });

    test('a plain POST (not proven idempotent) is still never auto-retried', () async {
      var attempts = 0;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          attempts++;
          throw const SocketException('dropped');
        }),
      );
      await expectLater(client.post('/orders/o1/messages'), throwsA(isA<SocketException>()));
      expect(attempts, 1);
    });
  });

  testWidgets('the menu error has a working "Try again"', (tester) async {
    final vendors = _FlakyVendors();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_FakeAuthController.new),
          vendorsRepositoryProvider.overrideWithValue(vendors),
          selectedVendorIdProvider.overrideWith((ref) => 'golden'),
        ],
        child: const MaterialApp(home: EateryMenuScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Unable to load this eatery.'), findsOneWidget);

    vendors.online = true;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(find.text('Golden Crust Bakery'), findsOneWidget);
    expect(find.text('Chicken Pie'), findsOneWidget);
  });
}
