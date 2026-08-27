import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/primary_button.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';
import 'package:run_it/features/wallet/presentation/wallet_screen.dart';

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

/// Seeds the basket with one line so a test can jump straight to Basket /
/// Checkout without depending on the async menu load resolving first.
class _SeededBasket extends BasketNotifier {
  _SeededBasket(this.itemId);
  final String itemId;
  @override
  Basket build() => Basket(
    eateryId: 'tantalizers',
    items: [BasketItem(menuItemId: itemId, quantity: 1)],
  );
}

class _LowBalanceWallet extends WalletBalanceController {
  @override
  int build() => 100;
}

void main() {
  group('BasketNotifier', () {
    test('add/remove/setQuantity manage lines correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(basketProvider.notifier);
      const jollof = MenuItem(
        id: 'jollof',
        eateryId: 'tantalizers',
        name: 'Signature jollof',
        description: '',
        price: 3100,
        packagingCost: 100,
        category: 'Mains',
        imageUrl: '',
        isAvailable: true,
      );
      const shawarma = MenuItem(
        id: 'wrap',
        eateryId: 'tantalizers',
        name: 'Chicken shawarma',
        description: '',
        price: 2200,
        packagingCost: 80,
        category: 'Quick bites',
        imageUrl: '',
        isAvailable: true,
      );
      const otherEateryItem = MenuItem(
        id: 'burger',
        eateryId: 'foodco',
        name: 'Burger',
        description: '',
        price: 2500,
        packagingCost: 50,
        category: 'Mains',
        imageUrl: '',
        isAvailable: true,
      );

      expect(notifier.add(jollof), AddToBasketResult.added);
      expect(container.read(basketProvider).items.single.quantity, 1);

      // Adding the same item again increments its line rather than
      // duplicating it.
      notifier.add(jollof);
      expect(container.read(basketProvider).items.single.quantity, 2);

      // A different item from the same eatery adds a second line.
      notifier.add(shawarma);
      expect(container.read(basketProvider).items.length, 2);

      notifier.setQuantity('jollof', 5);
      expect(
        container
            .read(basketProvider)
            .items
            .firstWhere((l) => l.menuItemId == 'jollof')
            .quantity,
        5,
      );

      notifier.remove('jollof');
      expect(
        container
            .read(basketProvider)
            .items
            .any((l) => l.menuItemId == 'jollof'),
        isFalse,
      );

      // An item from a different eatery can't silently mix into the basket.
      expect(notifier.add(otherEateryItem), AddToBasketResult.needsReplacement);
      expect(
        container
            .read(basketProvider)
            .items
            .any((l) => l.menuItemId == 'burger'),
        isFalse,
      );

      notifier.setQuantity('wrap', 0);
      expect(container.read(basketProvider).isEmpty, isTrue);
      expect(container.read(basketProvider).eateryId, isNull);
    });
  });

  group('Checkout', () {
    testWidgets(
      'blocks Place Order and offers an Add Funds shortcut when the wallet is short',
      (tester) async {
        final router = GoRouter(
          initialLocation: AppRoutes.checkout,
          routes: [
            GoRoute(
              path: AppRoutes.checkout,
              builder: (_, _) => const CheckoutScreen(),
            ),
            GoRoute(
              path: AppRoutes.studentWallet,
              builder: (_, _) => const WalletScreen(),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_studentSession()),
              ),
              basketProvider.overrideWith(
                () => _SeededBasket('jollof'),
              ), // ₦3,100
              walletBalanceProvider.overrideWith(
                () => _LowBalanceWallet(),
              ), // ₦100
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.text('Wallet balance is insufficient'), findsOneWidget);
        final placeOrderButton = tester.widget<PrimaryButton>(
          find.byType(PrimaryButton),
        );
        expect(placeOrderButton.onPressed, isNull);

        await tester.tap(find.text('Add funds to your wallet'));
        await tester.pumpAndSettle();
        expect(find.text('₦100'), findsOneWidget); // now on the Wallet screen
      },
    );

    testWidgets(
      'happy path: add an item, view basket, checkout, and land in My Orders Active tab',
      (tester) async {
        final router = GoRouter(
          initialLocation: AppRoutes.menu,
          routes: [
            GoRoute(
              path: AppRoutes.menu,
              builder: (_, _) => const EateryMenuScreen(),
            ),
            GoRoute(
              path: AppRoutes.basket,
              builder: (_, _) => const BasketScreen(),
            ),
            GoRoute(
              path: AppRoutes.checkout,
              builder: (_, _) => const CheckoutScreen(),
            ),
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
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_studentSession()),
              ),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        // Lets the mock eatery + menu FutureProviders resolve.
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.text('Signature jollof'), findsOneWidget);
        await tester.tap(find.text('Add').first);
        await tester.pump();
        // Lets the floating basket bar's appear/label-swap animation settle.
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('View Basket · 1 item'), findsOneWidget);
        await tester.tap(find.textContaining('View Basket'));
        await tester.pumpAndSettle();

        expect(find.text('Your basket'), findsOneWidget);
        expect(find.textContaining('Proceed to checkout'), findsOneWidget);
        await tester.tap(find.textContaining('Proceed to checkout'));
        await tester.pumpAndSettle();

        expect(find.text('Checkout'), findsOneWidget);
        final placeOrderFinder = find.textContaining('Place order');
        expect(placeOrderFinder, findsOneWidget);
        await tester.tap(placeOrderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Checkout->OrderTracking is a context.go(), then we jump straight
        // to My Orders the same way tapping its nav tab would.
        expect(find.text('Track your order'), findsOneWidget);
        router.go(AppRoutes.studentOrders);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Active (1)'), findsOneWidget);
        expect(find.text('Order confirmed'), findsOneWidget);
        expect(find.text('Confirmed'), findsOneWidget);
      },
    );
  });
}
