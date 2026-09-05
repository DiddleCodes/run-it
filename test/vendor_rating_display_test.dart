import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/vendor/application/my_vendor_profile_controller.dart';
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

class _RatedVendorProfileController extends MyVendorProfileController {
  @override
  Future<MyVendorProfile> build() async => const MyVendorProfile(
    id: 'vendor-1',
    businessName: "Mama Kemi's Kitchen",
    category: 'Nigerian',
    averageRating: 4.2,
    ratingCount: 9,
  );
}

class _UnratedVendorProfileController extends MyVendorProfileController {
  @override
  Future<MyVendorProfile> build() async =>
      const MyVendorProfile(id: 'vendor-2', businessName: 'New Spot', category: 'Snacks');
}

void main() {
  testWidgets("Task 48: the Restaurant Dashboard's own Profile tab shows its real rating and count", (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_restaurantSession())),
          myVendorProfileProvider.overrideWith(() => _RatedVendorProfileController()),
        ],
        child: const MaterialApp(home: RestaurantProfileScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('4.2 (9 ratings)'), findsOneWidget);
  });

  testWidgets('shows no rating line at all for a restaurant that has never been rated', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_restaurantSession())),
          myVendorProfileProvider.overrideWith(() => _UnratedVendorProfileController()),
        ],
        child: const MaterialApp(home: RestaurantProfileScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('ratings)'), findsNothing);
    expect(find.text('New Spot'), findsOneWidget);
  });
}
