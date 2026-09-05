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
}
