import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/demo_identity_service.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/core/widgets/primary_button.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
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
  _SeededBasket(this.itemId, {this.quantity = 1});
  final String itemId;
  final int quantity;
  @override
  Basket build() => Basket(
    eateryId: 'tantalizers',
    items: [BasketItem(menuItemId: itemId, quantity: quantity)],
  );
}

class _LowBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 100;
}

class _SufficientBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 50000;
}

/// Always resolves to the same fixed ids — a real `DemoIdentityService`
/// would hit the network (`POST /users`); tests just need any stable
/// strings, not real backend provisioning.
class _FakeDemoIdentityService extends DemoIdentityService {
  const _FakeDemoIdentityService();
  @override
  Future<String> ensureRestaurantUserId() async => 'demo-restaurant-1';
  @override
  Future<String> ensureRunnerUserId() async => 'demo-runner-1';
}

class _SucceedingEscrowRepository extends EscrowRepository {
  const _SucceedingEscrowRepository();
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
  }) async {}
}

/// Mirrors the backend's real 402 Payment Required rejection from
/// `OrderEscrowService.hold` (insufficient wallet balance at the moment of
/// the write) — the exact real failure case Task 8d asks to be handled.
class _InsufficientBalanceEscrowRepository extends EscrowRepository {
  const _InsufficientBalanceEscrowRepository();
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
    throw const ApiException(402, 'Insufficient wallet balance');
  }
}

/// Task 14: `menuProvider`/`selectedEateryProvider` now fetch real data via
/// `VendorsRepository.fetchMenu` (`GET /vendors/:id/menu`) instead of the
/// old `MockOrderingRepository` — this fake stands in for that network
/// call so Checkout/Basket tests keep resolving `jollof` without hitting a
/// real backend. Paired with `selectedVendorIdProvider.overrideWith` in
/// each test below, mirroring `_SeededBasket`'s own `eateryId: 'tantalizers'`.
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
      description: 'Smoky jollof rice, grilled chicken and plantain.',
      priceKobo: 310000,
      category: 'Mains',
      isAvailable: true,
      isMainMeal: true,
    ),
  ];

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async =>
      const VendorWithMenu(vendor: _vendor, items: _items);
}

final _vendorOverrides = [
  vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
  selectedVendorIdProvider.overrideWith((ref) => 'tantalizers'),
];

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
        isMainMeal: true,
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
        isMainMeal: false,
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
        isMainMeal: false,
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
              ..._vendorOverrides,
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
      'a hold failure (e.g. insufficient balance at write time) blocks order creation — never navigates to OrderTrackingScreen',
      (tester) async {
        final hapticCalls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call.arguments as String);
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        final router = GoRouter(
          initialLocation: AppRoutes.checkout,
          routes: [
            GoRoute(
              path: AppRoutes.checkout,
              builder: (_, _) => const CheckoutScreen(),
            ),
            GoRoute(
              path: AppRoutes.orderTracking,
              builder: (_, _) => const OrderTrackingScreen(),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_studentSession()),
              ),
              basketProvider.overrideWith(() => _SeededBasket('jollof')),
              walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
              demoIdentityServiceProvider.overrideWithValue(
                const _FakeDemoIdentityService(),
              ),
              escrowRepositoryProvider.overrideWithValue(
                const _InsufficientBalanceEscrowRepository(),
              ),
              ..._vendorOverrides,
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) =>
                  AppNotificationHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        final placeOrderFinder = find.textContaining('Place order');
        expect(placeOrderFinder, findsOneWidget);
        await tester.tap(placeOrderFinder);
        // The button tap itself fires PrimaryButton's own haptic — clear it
        // so only a checkout-success haptic (which shouldn't exist here)
        // would show up below.
        hapticCalls.clear();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // Never got to OrderTrackingScreen — still on Checkout, and the
        // backend's own rejection message is surfaced rather than a
        // generic one.
        expect(find.text('Track your order'), findsNothing);
        expect(find.text('Checkout'), findsOneWidget);
        expect(find.text('Insufficient wallet balance'), findsOneWidget);
        // Task 43: the checkout success haptic only fires once the escrow
        // hold actually succeeds — a rejected hold gets none.
        expect(hapticCalls, isEmpty);
      },
    );

    testWidgets(
      'happy path: add an item, view basket, checkout with a real hold, and land in My Orders Active tab',
      (tester) async {
        final hapticCalls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') hapticCalls.add(call.arguments as String);
          return null;
        });
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

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
              walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
              demoIdentityServiceProvider.overrideWithValue(
                const _FakeDemoIdentityService(),
              ),
              escrowRepositoryProvider.overrideWithValue(
                const _SucceedingEscrowRepository(),
              ),
              ..._vendorOverrides,
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        // Lets the eatery + menu FutureProviders resolve.
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
        // The tap itself resolves the (fully-faked, delay-free) checkout
        // chain synchronously inside this same await, PrimaryButton's own
        // tap haptic included — so isolate the checkout-success haptic by
        // count (button tap + success = 2) rather than trying to clear
        // between the two.
        final hapticsBeforeTap = hapticCalls.length;
        await tester.tap(placeOrderFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();

        // Checkout->OrderTracking is a context.go(), then we jump straight
        // to My Orders the same way tapping its nav tab would.
        expect(find.text('Track your order'), findsOneWidget);
        // Task 43: the button's own tap haptic, plus exactly one more for
        // the real escrow hold succeeding. OrderTrackingScreen's first
        // frame shows the checkout success beat rather than the normal
        // status line.
        expect(hapticCalls.sublist(hapticsBeforeTap), [
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.lightImpact',
        ]);
        expect(find.text('Payment confirmed'), findsOneWidget);
        router.go(AppRoutes.studentOrders);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Active (1)'), findsOneWidget);
        expect(find.text('Order received'), findsOneWidget);
        // Scoped to MyOrdersScreen: OrderTrackingScreen is still mounted in
        // a background shell branch, and its own Task 10 step labels
        // ('Preparing', 'Confirmed', ...) now legitimately share text with
        // this screen's separate compact mini-stepper — an unscoped
        // find.text would match both.
        expect(
          find.descendant(of: find.byType(MyOrdersScreen), matching: find.text('Confirmed')),
          findsOneWidget,
        );
      },
    );
  });

  group('Group Ordering (Task 66)', () {
    Widget harness(Widget child, {required int mainMealQuantity}) {
      final router = GoRouter(
        initialLocation: AppRoutes.basket,
        routes: [GoRoute(path: AppRoutes.basket, builder: (_, _) => child)],
      );
      return ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
          basketProvider.overrideWith(() => _SeededBasket('jollof', quantity: mainMealQuantity)),
          walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
          ..._vendorOverrides,
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets(
      'a standard basket over the 2 main-meal cap shows a clear message suggesting Group Order, and blocks checkout',
      (tester) async {
        await tester.pumpWidget(harness(const BasketScreen(), mainMealQuantity: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.textContaining('Standard orders allow up to 2'), findsOneWidget);
        expect(find.text('Switch'), findsOneWidget);
        expect(find.text('Remove main meals to continue'), findsOneWidget);
        final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
        expect(button.onPressed, isNull);
        // Still the plain ₦500 fee shown — the basket hasn't switched to
        // Group Order yet, it's just over the standard cap. The breakdown
        // sits below the fold, so scroll it into view first.
        await tester.scrollUntilVisible(find.text('Items'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('₦500'), findsWidgets);
      },
    );

    testWidgets(
      'tapping Switch on the cap notice enables Group Order, raises the cap, unblocks checkout, and shows the ₦650 fee',
      (tester) async {
        await tester.pumpWidget(harness(const BasketScreen(), mainMealQuantity: 3));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        await tester.tap(find.text('Switch'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // The over-cap notice for 3 main meals is gone (3 <= the new cap
        // of 4), and the toggle itself now reads on.
        expect(find.textContaining('Standard orders allow up to 2'), findsNothing);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
        final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
        expect(button.onPressed, isNotNull);
        expect(find.textContaining('Proceed to checkout'), findsOneWidget);
        // Delivery now reads ₦650 (₦500 flat + ₦150 Group Order surcharge)
        // — the surcharge is visible before the student ever reaches the
        // final "Place order" tap. The breakdown sits below the fold, so
        // scroll it into view first.
        await tester.scrollUntilVisible(find.text('Items'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('₦650'), findsWidgets);
        expect(find.textContaining('incl. ₦150 Group Order'), findsOneWidget);
      },
    );

    testWidgets('a group basket over the 4 main-meal cap shows the group-specific message and stays blocked', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const BasketScreen(), mainMealQuantity: 5));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      await tester.tap(find.text('Group Order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Group Order allows up to 4'), findsOneWidget);
      // No "Switch" action this time — enabling Group Order further
      // wouldn't help; the only fix is removing items.
      expect(find.text('Switch'), findsNothing);
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a standard basket at exactly 2 main meals is completely unaffected: ₦500 fee, checkout enabled', (
      tester,
    ) async {
      await tester.pumpWidget(harness(const BasketScreen(), mainMealQuantity: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(find.textContaining('Standard orders allow up to'), findsNothing);
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.onPressed, isNotNull);
      await tester.scrollUntilVisible(find.text('Items'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('₦500'), findsWidgets);
      expect(find.textContaining('₦650'), findsNothing);
    });

    testWidgets('removing a line item from an over-cap basket works exactly as it already did', (tester) async {
      await tester.pumpWidget(harness(const BasketScreen(), mainMealQuantity: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      expect(find.text('Remove main meals to continue'), findsOneWidget);

      // The same +/- stepper the basket line has always used — reducing
      // quantity below the cap needs no Group Order special-casing.
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();

      expect(find.textContaining('Proceed to checkout'), findsOneWidget);
      final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
