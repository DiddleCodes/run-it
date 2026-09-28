import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
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

/// [mains] of the ₦3,100 main meal, then [drinks] of the ₦700 drink.
class _SeededBasket extends BasketNotifier {
  _SeededBasket({required this.mains, this.drinks = 0});
  final int mains;
  final int drinks;
  @override
  Basket build() => Basket(
    eateryId: 'tantalizers',
    items: [
      if (mains > 0) BasketItem(menuItemId: 'jollof', quantity: mains),
      if (drinks > 0) BasketItem(menuItemId: 'malt', quantity: drinks),
    ],
  );
}

class _Wallet extends WalletBalanceController {
  @override
  Future<int> build() async => 500000;
}

class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository();

  static const _vendor = MyVendorProfile(
    id: 'tantalizers',
    businessName: 'Tantalizers',
    category: 'Meals',
    userId: 'demo-restaurant-1',
  );

  static const _items = [
    VendorMenuItem(
      id: 'jollof',
      name: 'Signature jollof',
      description: 'Smoky jollof rice.',
      priceKobo: 310000,
      category: 'Mains',
      isAvailable: true,
      isMainMeal: true,
    ),
    VendorMenuItem(
      id: 'malt',
      name: 'Chilled malt',
      description: 'Cold and bottled.',
      priceKobo: 70000,
      category: 'Drinks',
      isAvailable: true,
      isMainMeal: false,
    ),
  ];

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async => const VendorWithMenu(vendor: _vendor, items: _items);
}

const _groupTitle = 'Ordering for a group? 👀';
const _groupBody =
    'Solo orders are limited to 2 main meals. Switch to Group Order to add up to 4 meals in one delivery, '
    'for just ₦150 extra.';

Future<ProviderContainer> _pumpBasket(WidgetTester tester, {required int mains, int drinks = 0}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.basket,
    routes: [GoRoute(path: AppRoutes.basket, builder: (_, _) => const BasketScreen())],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
        basketProvider.overrideWith(() => _SeededBasket(mains: mains, drinks: drinks)),
        walletBalanceProvider.overrideWith(() => _Wallet()),
        vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
        selectedVendorIdProvider.overrideWith((ref) => 'tantalizers'),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
  return ProviderScope.containerOf(tester.element(find.byType(BasketScreen)));
}

int _quantity(ProviderContainer container, String id) =>
    container.read(basketProvider).items.where((l) => l.menuItemId == id).fold(0, (s, l) => s + l.quantity);

Future<void> _tapAddOnLine(WidgetTester tester, int lineIndex) async {
  await tester.tap(find.byIcon(Icons.add_rounded).at(lineIndex));
  await tester.pumpAndSettle();
}

void main() {
  group('Task 70: group-order popup at the main-meal cap', () {
    testWidgets('solo: a 3rd main meal asks first — "Keep solo order" adds nothing and stays solo', (tester) async {
      final container = await _pumpBasket(tester, mains: 2);

      await _tapAddOnLine(tester, 0);

      expect(find.text(_groupTitle), findsOneWidget);
      expect(find.text(_groupBody), findsOneWidget);
      expect(find.text('Switch to Group Order'), findsOneWidget);

      await tester.tap(find.text('Keep solo order'));
      await tester.pumpAndSettle();

      expect(_quantity(container, 'jollof'), 2);
      expect(container.read(checkoutFormProvider).isGroupOrder, isFalse);
    });

    testWidgets('solo: "Switch to Group Order" turns it on AND adds the meal they tried to add', (tester) async {
      final container = await _pumpBasket(tester, mains: 2);

      await _tapAddOnLine(tester, 0);
      await tester.tap(find.text('Switch to Group Order'));
      await tester.pumpAndSettle();

      expect(_quantity(container, 'jollof'), 3);
      expect(container.read(checkoutFormProvider).isGroupOrder, isTrue);
      await tester.scrollUntilVisible(find.text('Items'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('incl. ₦150 Group Order'), findsOneWidget);
      // Task 70: its own line — 5% of ₦9,300 food = ₦465.
      expect(find.text('Service fee (5%)'), findsOneWidget);
      expect(find.text('₦465'), findsOneWidget);
    });

    testWidgets('group: a 5th main meal is blocked, pointing to a second order', (tester) async {
      final container = await _pumpBasket(tester, mains: 4);
      container.read(checkoutFormProvider.notifier).setGroupOrder(true);
      await tester.pump();

      await _tapAddOnLine(tester, 0);

      expect(find.text('That’s the most for one order'), findsOneWidget);
      expect(find.textContaining('place a second order'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_quantity(container, 'jollof'), 4);
    });

    testWidgets('sides and drinks never count: adding a drink to 2 main meals never asks', (tester) async {
      final container = await _pumpBasket(tester, mains: 2, drinks: 1);

      await _tapAddOnLine(tester, 1);

      expect(find.text(_groupTitle), findsNothing);
      expect(_quantity(container, 'malt'), 2);
    });

    testWidgets('group: dropping to 2 main meals offers to switch back to solo (and switches when accepted)', (
      tester,
    ) async {
      final container = await _pumpBasket(tester, mains: 3);
      container.read(checkoutFormProvider.notifier).setGroupOrder(true);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Switch back to a solo order?'), findsOneWidget);
      expect(find.textContaining('won’t pay the ₦150 Group Order extra'), findsOneWidget);
      await tester.tap(find.text('Switch to solo'));
      await tester.pumpAndSettle();

      expect(_quantity(container, 'jollof'), 2);
      expect(container.read(checkoutFormProvider).isGroupOrder, isFalse);
    });

    testWidgets('group: "Keep Group Order" keeps it, and removing further does not ask again', (tester) async {
      final container = await _pumpBasket(tester, mains: 3);
      container.read(checkoutFormProvider.notifier).setGroupOrder(true);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep Group Order'));
      await tester.pumpAndSettle();
      expect(container.read(checkoutFormProvider).isGroupOrder, isTrue);

      await tester.tap(find.byIcon(Icons.remove_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Switch back to a solo order?'), findsNothing);
      expect(_quantity(container, 'jollof'), 1);
    });
  });

  testWidgets('Task 70: the Menu quick-add asks at the cap too, and switching adds the meal', (tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.menu,
      routes: [GoRoute(path: AppRoutes.menu, builder: (_, _) => const EateryMenuScreen())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
          basketProvider.overrideWith(() => _SeededBasket(mains: 2)),
          walletBalanceProvider.overrideWith(() => _Wallet()),
          vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
          selectedVendorIdProvider.overrideWith((ref) => 'tantalizers'),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    final container = ProviderScope.containerOf(tester.element(find.byType(EateryMenuScreen)));

    // The jollof card is first; its stepper's + is the first add icon.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text(_groupTitle), findsOneWidget);

    await tester.tap(find.text('Switch to Group Order'));
    await tester.pumpAndSettle();

    expect(_quantity(container, 'jollof'), 3);
    expect(container.read(checkoutFormProvider).isGroupOrder, isTrue);
  });
}
