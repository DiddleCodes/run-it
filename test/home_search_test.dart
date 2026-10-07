import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:run_it/core/network/api_client.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
import 'package:run_it/features/notifications/data/notifications_repository.dart';
import 'package:run_it/features/notifications/domain/app_notification.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';

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

const _vendors = [
  MyVendorProfile(id: 'v1', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries', averageRating: 4.6),
  MyVendorProfile(id: 'v2', businessName: 'Grillhouse 7', category: 'West African', averageRating: 4.1),
  MyVendorProfile(id: 'v3', businessName: "Mama Bisi's Kitchen", category: 'Nigerian'),
];

/// Each vendor's menu: (name, price in kobo).
const _menus = {
  'v1': [('Chicken Pie', 90000), ('Puff Puff (6pc)', 90000)],
  'v2': [('Suya Wrap', 250000)],
  'v3': [('Jollof Rice', 150000)],
};

/// Mirrors the backend's rules (category equals, name contains, both
/// case-insensitive and ANDed), records every call, and can hold a
/// response open to observe the in-between state.
class _FakeVendorsRepository extends VendorsRepository {
  final calls = <(String?, String?)>[];
  final filterCalls = <(String?, double?, int?)>[];
  Completer<void>? gate;

  @override
  Future<List<VendorCategoryOption>> fetchCategories() async => const [
    VendorCategoryOption(slug: 'bakery-pastries', label: 'Bakery & Pastries'),
    VendorCategoryOption(slug: 'nigerian', label: 'Nigerian'),
    VendorCategoryOption(slug: 'west-african', label: 'West African'),
  ];

  @override
  Future<VendorsPage> listVendors({
    String? category,
    String? search, String? sort, double? minRating, int? maxPriceKobo,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    calls.add((category, search));
    filterCalls.add((sort, minRating, maxPriceKobo));
    if (gate != null) await gate!.future;
    bool hits(String text) => search != null && text.toLowerCase().contains(search.toLowerCase());
    final items = <MyVendorProfile>[];
    for (final v in _vendors) {
      final menu = _menus[v.id]!.where((item) => maxPriceKobo == null || item.$2 <= maxPriceKobo);
      final matching = [for (final item in menu) if (hits(item.$1)) item.$1];
      if (category != null && v.category.toLowerCase() != category.toLowerCase()) continue;
      if (search != null && !hits(v.businessName) && matching.isEmpty) continue;
      if (minRating != null && (v.averageRating ?? 0) < minRating) continue;
      if (maxPriceKobo != null && menu.isEmpty) continue;
      items.add(
        MyVendorProfile.fromJson({
          'id': v.id,
          'businessName': v.businessName,
          'category': v.category,
          'averageRating': v.averageRating,
          'matchingItems': matching,
        }),
      );
    }
    if (sort == 'rating') items.sort((a, b) => (b.averageRating ?? -1).compareTo(a.averageRating ?? -1));
    return VendorsPage(items: items, total: items.length, page: page, limit: limit);
  }
}

/// A feed with [unread] unread notifications.
class _FakeNotificationsRepository extends NotificationsRepository {
  const _FakeNotificationsRepository(this.unread);
  final int unread;

  @override
  Future<NotificationFeed> list({required String token, int limit = 50}) async =>
      NotificationFeed(items: const [], unreadCount: unread);
}

Future<_FakeVendorsRepository> _pumpHome(WidgetTester tester, {int unreadNotifications = 0}) async {
  final repository = _FakeVendorsRepository();
  // The Campus Pick promo card (unrelated to search) overflows in the test
  // environment only: google_fonts can't fetch its font here, and the
  // fallback's metrics are taller than the real font's in the card's fixed
  // 200px text column. On device it renders fine; its layout is covered by
  // dynamic_type_overflow_test. Every other error still fails the test.
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    final context = details.informationCollector?.call().map((node) => node.toStringDeep()).join() ?? '';
    final fromPromoCard = details.exceptionAsString().contains('overflowed') && context.contains('_PromoCard');
    if (!fromPromoCard) reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
  // A tall phone, so the "Popular around campus" row is on screen (a
  // sliver below the fold isn't built at all).
  tester.view.physicalSize = const Size(2400, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_FakeAuthController.new),
        vendorsRepositoryProvider.overrideWithValue(repository),
        notificationsRepositoryProvider.overrideWithValue(_FakeNotificationsRepository(unreadNotifications)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return repository;
}

Finder get _searchField => find.byType(TextField);

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_searchField, text);
  await tester.pump(const Duration(milliseconds: 360)); // past the 350ms debounce
  await tester.pump(const Duration(milliseconds: 20)); // the response
}

void main() {
  group('Home bell', () {
    testWidgets('shows how many notifications are unread', (tester) async {
      await _pumpHome(tester, unreadNotifications: 3);
      expect(find.byKey(const ValueKey('bell-badge')), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 3 unread'), findsOneWidget);
    });

    testWidgets('shows no badge when everything is read', (tester) async {
      await _pumpHome(tester);
      expect(find.byKey(const ValueKey('bell-badge')), findsNothing);
      expect(find.bySemanticsLabel('Notifications'), findsOneWidget);
    });

    testWidgets('caps the badge at 9+', (tester) async {
      await _pumpHome(tester, unreadNotifications: 14);
      expect(find.text('9+'), findsOneWidget);
    });
  });

  group('Home search bar', () {
    testWidgets('is one control: the field draws no box of its own inside the pill', (tester) async {
      await _pumpHome(tester);
      final decoration = tester.widget<TextField>(_searchField).decoration!;

      expect(decoration.filled, isFalse);
      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
    });

    testWidgets('debounces typing: one request per pause, not per keystroke', (tester) async {
      final repository = await _pumpHome(tester);
      final before = repository.calls.length;

      for (final partial in ['g', 'gr', 'gri', 'gril', 'grill']) {
        await tester.enterText(_searchField, partial);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 360));

      expect(repository.calls.skip(before), [(null, 'grill')]);
    });
  });

  group('Home search + filters narrow the real list', () {
    testWidgets('a category chip narrows results', (tester) async {
      await _pumpHome(tester);
      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Grillhouse 7'), findsOneWidget);

      await tester.tap(find.text('Nigerian').first); // the chip (the card subtitle says it too)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text("Mama Bisi's Kitchen"), findsOneWidget);
      expect(find.text('Golden Crust Bakery'), findsNothing);
    });

    testWidgets('text search narrows results', (tester) async {
      await _pumpHome(tester);
      await _type(tester, 'grill');

      expect(find.text('Grillhouse 7'), findsOneWidget);
      expect(find.text('Golden Crust Bakery'), findsNothing);
    });

    testWidgets('a category and a search combine (both apply, not one or the other)', (tester) async {
      final repository = await _pumpHome(tester);
      await tester.tap(find.text('Nigerian').first); // the chip (the card subtitle says it too)
      await tester.pump(const Duration(milliseconds: 50));

      await _type(tester, 'bakery');

      expect(repository.calls.last, ('Nigerian', 'bakery'));
      expect(find.text('Golden Crust Bakery'), findsNothing);
      expect(find.text('No vendors found for your search.'), findsOneWidget);
    });

    testWidgets('no match shows a real message, not a blank row', (tester) async {
      await _pumpHome(tester);
      await _type(tester, 'zzz');

      expect(find.text('No vendors found for your search.'), findsOneWidget);
    });

    testWidgets('a new search keeps the current results on screen while it loads', (tester) async {
      final repository = await _pumpHome(tester);
      repository.gate = Completer<void>();

      await tester.enterText(_searchField, 'grill');
      await tester.pump(const Duration(milliseconds: 360));

      // Mid-request: the previous results are still there (no skeleton
      // flash), with the small spinner by the heading.
      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.gate!.complete();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Golden Crust Bakery'), findsNothing);
      expect(find.text('Grillhouse 7'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('pulling down re-fetches (the error state promises exactly this)', (tester) async {
      final repository = await _pumpHome(tester);
      final before = repository.calls.length;

      await tester.fling(find.text('What are you\ncraving today?'), const Offset(0, 400), 1000);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(repository.calls.length, greaterThan(before));
    });
  });

  group('Search matches dishes, not just store names', () {
    testWidgets('"puff" finds the bakery that sells Puff Puff, and the card says why', (tester) async {
      await _pumpHome(tester);
      await _type(tester, 'puff');

      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Has Puff Puff (6pc)'), findsOneWidget);
      expect(find.text('Grillhouse 7'), findsNothing);
    });

    testWidgets('"jollof" finds the kitchen that sells Jollof Rice', (tester) async {
      await _pumpHome(tester);
      await _type(tester, 'jollof');

      expect(find.text("Mama Bisi's Kitchen"), findsOneWidget);
      expect(find.text('Has Jollof Rice'), findsOneWidget);
      expect(find.text('Golden Crust Bakery'), findsNothing);
    });

    testWidgets('a store found by its own name shows its usual subtitle', (tester) async {
      await _pumpHome(tester);
      await _type(tester, 'grill');

      expect(find.text('Grillhouse 7'), findsOneWidget);
      expect(find.textContaining('Has '), findsNothing);
    });
  });

  group('The filter icon is a working feature', () {
    Future<void> openFilters(WidgetTester tester) async {
      await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> showResults(WidgetTester tester) async {
      await tester.tap(find.text('Show results'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('choices apply on "Show results": refetched with them, and the icon shows how many are on', (
      tester,
    ) async {
      final repository = await _pumpHome(tester);
      await openFilters(tester);
      expect(find.text('Filters'), findsOneWidget);

      await tester.tap(find.text('Top rated'));
      await tester.tap(find.text('★ 4.5+'));
      await tester.tap(find.text('₦1,000.00'));
      await tester.pump();
      // Nothing refetched yet — only on "Show results".
      expect(repository.filterCalls.last, (null, null, null));

      await showResults(tester);

      expect(repository.filterCalls.last, ('rating', 4.5, 100000));
      expect(find.text('Golden Crust Bakery'), findsOneWidget);
      expect(find.text('Grillhouse 7'), findsNothing);
      expect(find.text("Mama Bisi's Kitchen"), findsNothing);
      expect(find.text('3'), findsOneWidget); // the badge on the filter icon
    });

    testWidgets('closing the sheet does not pop the keyboard back up over the results', (tester) async {
      await _pumpHome(tester);
      await tester.tap(_searchField);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await openFilters(tester);
      await tester.tap(find.text('₦1,000.00'));
      await showResults(tester);

      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pump(const Duration(seconds: 1)); // card fade-ins
    });

    testWidgets('top rated orders best-first', (tester) async {
      await _pumpHome(tester);
      await openFilters(tester);
      await tester.tap(find.text('Top rated'));
      await showResults(tester);

      final golden = tester.getTopLeft(find.text('Golden Crust Bakery')).dx;
      final grill = tester.getTopLeft(find.text('Grillhouse 7')).dx;
      final unrated = tester.getTopLeft(find.text("Mama Bisi's Kitchen")).dx;
      expect(golden < grill && grill < unrated, isTrue);
    });

    testWidgets('filters that match nothing say so, and "Clear filters" brings the list back', (tester) async {
      await _pumpHome(tester);
      await tester.tap(find.text('Nigerian').first);
      await tester.pump(const Duration(milliseconds: 50));
      await openFilters(tester);
      await tester.tap(find.text('★ 4.0+'));
      await showResults(tester);

      expect(find.text('No vendors match these filters.'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text("Mama Bisi's Kitchen"), findsOneWidget);
      expect(find.text('No vendors match these filters.'), findsNothing);      await tester.pump(const Duration(seconds: 1)); // card fade-ins
    });

    testWidgets('Reset in the sheet goes back to everything', (tester) async {
      final repository = await _pumpHome(tester);
      await openFilters(tester);
      await tester.tap(find.text('★ 4.5+'));
      await showResults(tester);
      expect(find.text('Grillhouse 7'), findsNothing);

      await openFilters(tester);
      await tester.tap(find.text('Reset'));
      await showResults(tester);

      expect(repository.filterCalls.last, (null, null, null));
      expect(find.text('Grillhouse 7'), findsOneWidget);      await tester.pump(const Duration(seconds: 1)); // card fade-ins
    });
  });

  test('the repository sends the filters to GET /vendors as the backend expects', () async {
    late Uri requested;
    final repository = VendorsRepository(
      client: ApiClient(
        httpClient: MockClient((request) async {
          requested = request.url;
          return http.Response('{"items":[],"total":0,"page":1,"limit":20}', 200);
        }),
      ),
    );

    await repository.listVendors(search: 'puff', sort: 'rating', minRating: 4.5, maxPriceKobo: 100000, token: 't');

    expect(requested.path, '/vendors');
    expect(requested.queryParameters, {
      'page': '1',
      'limit': '20',
      'search': 'puff',
      'sort': 'rating',
      'minRating': '4.5',
      'maxPriceKobo': '100000',
    });
  });
}
