import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/vendor/application/my_vendor_profile_controller.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/vendor/presentation/restaurant_menu_screen.dart';

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

class _FakeMyVendorProfileController extends MyVendorProfileController {
  @override
  Future<MyVendorProfile> build() async =>
      const MyVendorProfile(id: 'vendor-1', businessName: "Mama Kemi's Kitchen", category: 'Nigerian');
}

/// In-memory stand-in for the real `/vendors/*` menu-item endpoints —
/// enough to exercise create/update/delete/availability without a live
/// backend.
class _FakeVendorsRepository extends VendorsRepository {
  final List<VendorMenuItem> items = [];
  int _nextId = 1;

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async => VendorWithMenu(
    vendor: const MyVendorProfile(id: 'vendor-1', businessName: "Mama Kemi's Kitchen", category: 'Nigerian'),
    items: List.of(items),
  );

  @override
  Future<VendorMenuItem> createMenuItem({
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
    required String token,
  }) async {
    final item = VendorMenuItem(
      id: 'item-${_nextId++}',
      name: name,
      description: description,
      priceKobo: priceKobo,
      photoUrl: photoUrl,
      category: category,
      isAvailable: true,
    );
    items.add(item);
    return item;
  }

  @override
  Future<VendorMenuItem> updateMenuItem({
    required String itemId,
    required String name,
    String? description,
    required int priceKobo,
    String? photoUrl,
    required String category,
    required String token,
  }) async {
    final index = items.indexWhere((i) => i.id == itemId);
    final updated = VendorMenuItem(
      id: itemId,
      name: name,
      description: description,
      priceKobo: priceKobo,
      photoUrl: photoUrl,
      category: category,
      isAvailable: items[index].isAvailable,
    );
    items[index] = updated;
    return updated;
  }

  @override
  Future<void> setMenuItemAvailability({
    required String itemId,
    required bool isAvailable,
    required String token,
  }) async {
    final index = items.indexWhere((i) => i.id == itemId);
    final current = items[index];
    items[index] = VendorMenuItem(
      id: current.id,
      name: current.name,
      description: current.description,
      priceKobo: current.priceKobo,
      photoUrl: current.photoUrl,
      category: current.category,
      isAvailable: isAvailable,
    );
  }

  @override
  Future<void> deleteMenuItem({required String itemId, required String token}) async {
    items.removeWhere((i) => i.id == itemId);
  }
}

Widget _harness(_FakeVendorsRepository repo) {
  final router = GoRouter(
    initialLocation: AppRoutes.restaurantMenu,
    routes: [
      GoRoute(path: AppRoutes.restaurantMenu, builder: (_, _) => const RestaurantMenuScreen()),
      GoRoute(path: AppRoutes.restaurantMenuAdd, builder: (_, _) => const RestaurantMenuEditScreen()),
      GoRoute(
        path: AppRoutes.restaurantMenuEdit,
        builder: (_, state) {
          final extra = state.extra;
          return RestaurantMenuEditScreen(item: extra is VendorMenuItem ? extra : null);
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(() => _FakeAuthController(_restaurantSession())),
      myVendorProfileProvider.overrideWith(() => _FakeMyVendorProfileController()),
      vendorsRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => AppNotificationHost(child: child ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  testWidgets('adding a menu item calls the backend and the new item appears in the list', (tester) async {
    final repo = _FakeVendorsRepository();
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Your menu is empty'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Suya Platter'); // Name
    await tester.enterText(fields.at(1), '3500'); // Price
    await tester.tap(find.text('+ New'));
    await tester.pump();
    // Inserted between the category chips and the (always-present)
    // Description field, so it's index 2, not the last TextField overall.
    await tester.enterText(find.byType(TextField).at(2), 'Mains');
    // Scoped to the IconButton specifically — ValidatedField's own inline
    // "valid" checkmark uses the same icon and would otherwise collide.
    final confirmCategoryButton = find.widgetWithIcon(IconButton, Icons.check_circle_rounded);
    await tester.ensureVisible(confirmCategoryButton);
    await tester.pumpAndSettle();
    await tester.tap(confirmCategoryButton);
    await tester.pump();

    await tester.ensureVisible(find.text('Add to Menu'));
    await tester.tap(find.text('Add to Menu'));
    await tester.pumpAndSettle();

    expect(repo.items, hasLength(1));
    expect(repo.items.single.name, 'Suya Platter');
    expect(repo.items.single.priceKobo, 350000);
    expect(repo.items.single.category, 'Mains');
    expect(find.text('Suya Platter'), findsOneWidget);
  });

  testWidgets('editing an existing item prefills the form and updates it on save', (tester) async {
    final repo = _FakeVendorsRepository();
    repo.items.add(
      const VendorMenuItem(id: 'item-1', name: 'Jollof Rice', priceKobo: 300000, category: 'Mains', isAvailable: true),
    );
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Jollof Rice'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Item'), findsOneWidget);
    // Prefilled from the existing item, not asked for again from scratch.
    final nameField = tester.widget<TextField>(find.byType(TextField).at(0));
    expect(nameField.controller?.text, 'Jollof Rice');
    expect(find.text('3000'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'Party Jollof Rice');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(repo.items.single.name, 'Party Jollof Rice');
    expect(find.text('Party Jollof Rice'), findsOneWidget);
  });

  testWidgets('toggling availability calls the backend and flips the switch to reflect the confirmed state', (
    tester,
  ) async {
    final repo = _FakeVendorsRepository();
    repo.items.add(
      const VendorMenuItem(id: 'item-1', name: 'Jollof Rice', priceKobo: 300000, category: 'Mains', isAvailable: true),
    );
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.items.single.isAvailable, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('deleting a menu item asks for confirmation, then removes it for good', (tester) async {
    final repo = _FakeVendorsRepository();
    repo.items.add(
      const VendorMenuItem(id: 'item-1', name: 'Jollof Rice', priceKobo: 300000, category: 'Mains', isAvailable: true),
    );
    await tester.pumpWidget(_harness(repo));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Delete "Jollof Rice"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.items, hasLength(1));

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repo.items, isEmpty);
    expect(find.text('Your menu is empty'), findsOneWidget);
  });
}
