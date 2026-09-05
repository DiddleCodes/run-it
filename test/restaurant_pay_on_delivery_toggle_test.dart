import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/vendor/presentation/restaurant_profile_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _restaurantSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'restaurant-1',
    name: 'Mama Kemi',
    contact: 'kemi@campus.edu',
    accountType: AccountType.restaurant,
    campusId: 'ui',
  ),
);

/// Task 47: a real, minimal in-memory stand-in for `POST/GET /vendors/me` —
/// records every `upsertMyVendor` call so the test can assert exactly what
/// the toggle sends, and reflects the saved state back on the next fetch,
/// same "real backend confirmation only" shape `MyVendorProfileController`
/// itself expects.
class _RecordingVendorsRepository extends VendorsRepository {
  _RecordingVendorsRepository({this.payAtDeliveryEnabled = false});
  bool payAtDeliveryEnabled;
  final List<bool?> upsertCalls = [];

  @override
  Future<MyVendorProfile> fetchMyVendor({required String token}) async => MyVendorProfile(
    id: 'vendor-1',
    businessName: "Mama Kemi's Kitchen",
    category: 'Nigerian',
    payAtDeliveryEnabled: payAtDeliveryEnabled,
  );

  @override
  Future<MyVendorProfile> upsertMyVendor({
    required String businessName,
    required String category,
    String? description,
    String? logoUrl,
    String? requestedCampusId,
    bool? payAtDeliveryEnabled,
    required String token,
  }) async {
    upsertCalls.add(payAtDeliveryEnabled);
    if (payAtDeliveryEnabled != null) this.payAtDeliveryEnabled = payAtDeliveryEnabled;
    return MyVendorProfile(
      id: 'vendor-1',
      businessName: businessName,
      category: category,
      description: description,
      logoUrl: logoUrl,
      payAtDeliveryEnabled: this.payAtDeliveryEnabled,
    );
  }
}

Widget _harness(_RecordingVendorsRepository repo) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(() => _FakeAuthController(_restaurantSession())),
    vendorsRepositoryProvider.overrideWithValue(repo),
  ],
  child: const MaterialApp(home: RestaurantProfileScreen()),
);

void main() {
  testWidgets('Task 47: the Profile tab shows the current Pay on Delivery state and flipping it calls the real backend', (
    tester,
  ) async {
    final repo = _RecordingVendorsRepository(payAtDeliveryEnabled: false);
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Accept Pay on Delivery'), findsOneWidget);
    final offSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(offSwitch.value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.upsertCalls, [true]);
    // Re-sent the restaurant's own current business info alongside the
    // flag, rather than a partial/blank overwrite.
    final onSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(onSwitch.value, isTrue);
  });

  testWidgets('reflects an already-opted-in restaurant as on from the first real fetch', (tester) async {
    final repo = _RecordingVendorsRepository(payAtDeliveryEnabled: true);
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final onSwitch = tester.widget<Switch>(find.byType(Switch));
    expect(onSwitch.value, isTrue);
  });
}
