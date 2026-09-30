import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
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
  MyVendorProfile(id: 'v1', businessName: 'Golden Crust Bakery', category: 'Bakery & Pastries'),
  MyVendorProfile(id: 'v2', businessName: 'Grillhouse 7', category: 'West African'),
  MyVendorProfile(id: 'v3', businessName: "Mama Bisi's Kitchen", category: 'Nigerian'),
];

/// Mirrors the backend's rules (category equals, name contains, both
/// case-insensitive and ANDed), records every call, and can hold a
/// response open to observe the in-between state.
class _FakeVendorsRepository extends VendorsRepository {
  final calls = <(String?, String?)>[];
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
    String? search,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    calls.add((category, search));
    if (gate != null) await gate!.future;
    final items = _vendors
        .where((v) => category == null || v.category.toLowerCase() == category.toLowerCase())
        .where((v) => search == null || v.businessName.toLowerCase().contains(search.toLowerCase()))
        .toList();
    return VendorsPage(items: items, total: items.length, page: page, limit: limit);
  }
}

Future<_FakeVendorsRepository> _pumpHome(WidgetTester tester) async {
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
}
