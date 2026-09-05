import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

/// Seeds the basket with [quantity] of the same item — a quantity high
/// enough pushes the real order total past Task 47's ₦10,000 Pay on
/// Delivery cap without needing a second fake menu item priced above it.
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

class _SufficientBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 500000;
}

/// Wallet balance is deliberately zero here — proves Pay on Delivery never
/// depends on (or is blocked by) the student's wallet balance at all.
class _EmptyWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 0;
}

class _FakeDemoIdentityService extends DemoIdentityService {
  const _FakeDemoIdentityService();
  @override
  Future<String> ensureRestaurantUserId() async => 'demo-restaurant-1';
}

/// Records every `hold()` call's arguments — what these tests assert
/// against, rather than a real network effect.
class _RecordingEscrowRepository extends EscrowRepository {
  _RecordingEscrowRepository();
  final List<Map<String, dynamic>> calls = [];

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
    calls.add({'grossAmountKobo': grossAmountKobo, 'paymentMethod': paymentMethod});
  }
}

/// Same shape as `basket_checkout_flow_test.dart`'s own fake — a single
/// menu item, with the vendor's `payAtDeliveryEnabled` opt-in configurable
/// per test.
class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository({required this.payAtDeliveryEnabled});
  final bool payAtDeliveryEnabled;

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
  Future<VendorWithMenu> fetchMenu(String vendorId) async => VendorWithMenu(
    vendor: MyVendorProfile(
      id: 'tantalizers',
      businessName: 'Tantalizers',
      category: 'Meals',
      userId: 'demo-restaurant-1',
      payAtDeliveryEnabled: payAtDeliveryEnabled,
    ),
    items: _items,
  );
}

List<Override> _vendorOverrides({required bool payAtDeliveryEnabled}) => [
  vendorsRepositoryProvider.overrideWithValue(_FakeVendorsRepository(payAtDeliveryEnabled: payAtDeliveryEnabled)),
  selectedVendorIdProvider.overrideWith((ref) => 'tantalizers'),
];

Widget _checkoutHarness({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: AppRoutes.checkout,
    routes: [
      GoRoute(path: AppRoutes.checkout, builder: (_, _) => const CheckoutScreen()),
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const OrderTrackingScreen()),
      GoRoute(path: AppRoutes.studentOrders, builder: (_, _) => const Text('MY_ORDERS')),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  group('Task 47: Pay on Delivery at checkout', () {
    testWidgets(
      'an opted-in restaurant, under the cap: Pay on Delivery is selectable and places the order with no wallet balance at all',
      (tester) async {
        final escrow = _RecordingEscrowRepository();
        await tester.pumpWidget(
          _checkoutHarness(
            overrides: [
              authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
              basketProvider.overrideWith(() => _SeededBasket('jollof')), // ₦3,100 — under the cap
              walletBalanceProvider.overrideWith(() => _EmptyWallet()), // ₦0
              demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
              escrowRepositoryProvider.overrideWithValue(escrow),
              ..._vendorOverrides(payAtDeliveryEnabled: true),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.text('Pay on Delivery'), findsOneWidget);
        expect(find.text('Pay cash when your order arrives.'), findsOneWidget);

        await tester.tap(find.text('Pay on Delivery'));
        await tester.pump();

        // A zero wallet balance never blocks Place Order once Pay on
        // Delivery is selected.
        final placeOrderButton = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
        expect(placeOrderButton.onPressed, isNotNull);
        expect(find.textContaining('Place order'), findsOneWidget);

        await tester.tap(find.textContaining('Place order'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(escrow.calls, hasLength(1));
        expect(escrow.calls.single['paymentMethod'], 'pay_on_delivery');
      },
    );

    testWidgets(
      "a restaurant that hasn't opted in: Pay on Delivery is greyed out with the honest restaurant-declined message",
      (tester) async {
        await tester.pumpWidget(
          _checkoutHarness(
            overrides: [
              authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
              basketProvider.overrideWith(() => _SeededBasket('jollof')),
              walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
              demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
              escrowRepositoryProvider.overrideWithValue(_RecordingEscrowRepository()),
              ..._vendorOverrides(payAtDeliveryEnabled: false),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.text('This restaurant requires payment before delivery.'), findsOneWidget);

        await tester.tap(find.text('Pay on Delivery'));
        await tester.pump();

        // Never actually selected — tapping only explains why (as an app
        // notification, hence two matches: the option's own subtitle plus
        // the toast), same as the Card/Bank stub option.
        expect(find.text('This restaurant requires payment before delivery.'), findsWidgets);
        expect(find.text('RUN IT Wallet'), findsOneWidget);
      },
    );

    testWidgets(
      "an order over ₦10,000: Pay on Delivery is greyed out with the honest value-cap message, even for an opted-in restaurant",
      (tester) async {
        await tester.pumpWidget(
          _checkoutHarness(
            overrides: [
              authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
              // 5 x ₦3,100 = ₦15,500 food subtotal alone — comfortably over
              // the ₦10,000 cap once delivery/service fees are added too.
              basketProvider.overrideWith(() => _SeededBasket('jollof', quantity: 5)),
              walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
              demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
              escrowRepositoryProvider.overrideWithValue(_RecordingEscrowRepository()),
              ..._vendorOverrides(payAtDeliveryEnabled: true),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        expect(find.textContaining("isn't available for orders over"), findsOneWidget);
      },
    );

    testWidgets(
      'the existing wallet-payment checkout flow is completely unaffected: still sends paymentMethod: wallet',
      (tester) async {
        final escrow = _RecordingEscrowRepository();
        await tester.pumpWidget(
          _checkoutHarness(
            overrides: [
              authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
              basketProvider.overrideWith(() => _SeededBasket('jollof')),
              walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
              demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
              escrowRepositoryProvider.overrideWithValue(escrow),
              ..._vendorOverrides(payAtDeliveryEnabled: true),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        // Wallet is selected by default — never touch Pay on Delivery.
        await tester.tap(find.textContaining('Place order'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(escrow.calls, hasLength(1));
        expect(escrow.calls.single['paymentMethod'], 'wallet');
      },
    );
  });
}
