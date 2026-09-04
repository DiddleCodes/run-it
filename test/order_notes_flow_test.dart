import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/demo_identity_service.dart';
import 'package:run_it/core/network/escrow_repository.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
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

class _SufficientBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 50000;
}

class _FakeDemoIdentityService extends DemoIdentityService {
  const _FakeDemoIdentityService();
  @override
  Future<String> ensureRestaurantUserId() async => 'demo-restaurant-1';
  @override
  Future<String> ensureRunnerUserId() async => 'demo-runner-1';
}

/// Serves one real vendor with a real userId — so this test can also
/// confirm the escrow hold's `restaurantUserId`/`vendorId` reflect the
/// vendor the student actually ordered from, not the demo stand-in.
class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository();
  static const _vendor = MyVendorProfile(
    id: 'vendor-tantalizers',
    businessName: 'Tantalizers',
    category: 'Meals',
    userId: 'vendor-owner-1',
  );
  static const _items = [
    VendorMenuItem(id: 'jollof', name: 'Signature jollof', priceKobo: 310000, category: 'Mains', isAvailable: true),
  ];

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async => const VendorWithMenu(vendor: _vendor, items: _items);
}

/// Captures exactly what the checkout flow sends, so this test can assert
/// on the real per-item payload (Task 14 Part C/A) rather than just on
/// what the UI displays.
class _RecordingEscrowRepository extends EscrowRepository {
  const _RecordingEscrowRepository();
  static final calls = <Map<String, dynamic>>[];

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
    String? deliveryLocationLabel,
  }) async {
    calls.add({
      'restaurantUserId': restaurantUserId,
      'vendorId': vendorId,
      'items': items,
      'grossAmountKobo': grossAmountKobo,
      'deliveryFeeKobo': deliveryFeeKobo,
    });
  }
}

Widget _harness() {
  final router = GoRouter(
    initialLocation: AppRoutes.menu,
    routes: [
      GoRoute(path: AppRoutes.menu, builder: (_, _) => const EateryMenuScreen(vendorId: 'vendor-tantalizers')),
      GoRoute(path: AppRoutes.basket, builder: (_, _) => const BasketScreen()),
      GoRoute(path: AppRoutes.checkout, builder: (_, _) => const CheckoutScreen()),
      GoRoute(path: AppRoutes.orderTracking, builder: (_, _) => const OrderTrackingScreen()),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
      walletBalanceProvider.overrideWith(() => _SufficientBalanceWallet()),
      demoIdentityServiceProvider.overrideWithValue(const _FakeDemoIdentityService()),
      vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
      escrowRepositoryProvider.overrideWithValue(const _RecordingEscrowRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => _RecordingEscrowRepository.calls.clear());

  testWidgets(
    "a note added in Item Options survives through Basket and Checkout into the real escrow payload (Task 14 Part C)",
    (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));

      // Item Options sheet — Task 6's sheet, extended with a notes field.
      await tester.tap(find.text('Signature jollof'));
      await tester.pumpAndSettle();
      expect(find.text('Add a note'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'No onions please');
      await tester.tap(find.text('Add to Basket — ₦3100'));
      await tester.pumpAndSettle();

      // Basket screen shows the note preview (Task 14 Part C2).
      await tester.tap(find.textContaining('View Basket'));
      await tester.pumpAndSettle();
      expect(find.text('"No onions please"'), findsOneWidget);

      await tester.tap(find.textContaining('Proceed to checkout'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Place order'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(_RecordingEscrowRepository.calls, hasLength(1));
      final call = _RecordingEscrowRepository.calls.single;
      // The real vendor's own identity — not the demo stand-in — now that
      // it's known (Task 14).
      expect(call['restaurantUserId'], 'vendor-owner-1');
      expect(call['vendorId'], 'vendor-tantalizers');
      final items = call['items'] as List<EscrowOrderItem>;
      expect(items, hasLength(1));
      expect(items.single.name, 'Signature jollof');
      expect(items.single.notes, 'No onions please');

      // Task 15: delivery fee now travels separately from the food
      // subtotal, so the backend can split it (and the runner's cut of it)
      // correctly instead of treating the whole order as one commissionable
      // amount. grossAmountKobo here is just the ₦3100 jollof plus the
      // ₦150 service fee (no packaging cost on this fixture) — the zone's
      // delivery fee must not be folded into it.
      expect(call['grossAmountKobo'], 325000);
      expect(
        call['deliveryFeeKobo'],
        anyOf(45000, 35000, 50000), // one of DeliveryFeeZone's *100 fees
      );
    },
  );
}
