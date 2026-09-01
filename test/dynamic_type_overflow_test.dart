import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_nav_shell.dart';
import 'package:run_it/core/widgets/primary_button.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/auth/presentation/welcome_back_screen.dart';
import 'package:run_it/features/auth/presentation/widgets/campus_picker_field.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
import 'package:run_it/features/ordering/presentation/ordering_screens.dart';
import 'package:run_it/features/payout/domain/payout_models.dart';
import 'package:run_it/features/payout/presentation/widgets/bank_picker_field.dart';
import 'package:run_it/features/payout/presentation/widgets/payout_account_form.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/features/ordering/application/order_tracking_controller.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/vendor/presentation/restaurant_metrics_screen.dart';
import 'package:run_it/features/vendor/presentation/restaurant_orders_screen.dart';
import 'package:run_it/features/vendor/presentation/widgets/category_picker_field.dart';

/// Regression convention for TASK 8a's overflow-bug class: render the
/// app's core reusable cards at a spread of Dynamic Type scale factors and
/// assert nothing throws a `RenderFlex overflowed` (or any other) render
/// exception. 1.0 is the default; 1.3 and 2.0 mirror the larger end of
/// iOS's standard (non-"accessibility") Dynamic Type range — exactly the
/// range that broke the runner nav bar, the Campus Pick card, the KYC
/// pending screen, and the home-screen vendor cards over the course of
/// this session before their underlying fixed-height containers were
/// fixed. Any new reusable card should get a line added to [_scales] loop
/// coverage here rather than waiting to be discovered as a fifth bug.
const _scales = [1.0, 1.3, 2.0];

/// Wraps [child] in a real widget tree — `ProviderScope` + a
/// `MaterialApp.builder` hook that overrides the ambient `MediaQuery`'s
/// text scaler — since `MaterialApp` derives its own `MediaQuery` from the
/// platform and would otherwise clobber one supplied above it.
Widget _atScale(
  double scale,
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: widget!,
      ),
      home: child,
    ),
  );
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _restaurantSessionForScale() => AuthSession(
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

/// In-memory stand-in for [VendorsRepository], same convention as
/// `restaurant_orders_screen_test.dart` / `restaurant_menu_crud_test.dart` —
/// seeded here with a deliberately long order id, item name, and note, and
/// a top-selling item with a long name, since those are exactly the values
/// that overflowed the order card header and (via the metrics range chips'
/// long labels) the preset row before both were fixed.
class _ScaleTestVendorsRepository extends VendorsRepository {
  const _ScaleTestVendorsRepository();

  @override
  Future<VendorOrdersPage> fetchOrders({
    RestaurantOrderStatus? status,
    int page = 1,
    int limit = 20,
    required String token,
  }) async {
    final order = RestaurantOrder(
      id: 'a1b2c3d4-e5f6-4789-90ab-cdef01234567',
      status: RestaurantOrderStatus.readyForPickup,
      pickupCode: '4821',
      totalKobo: 1250000,
      deliveryLocationLabel: 'Hostel B',
      createdAt: DateTime(2026, 1, 1),
      items: const [
        RestaurantOrderItem(
          id: 'item-1',
          name: 'Special Jollof Rice with Grilled Chicken and Fried Plantain',
          quantity: 3,
          priceKobo: 350000,
          notes: 'No onions please, extra spicy, and can you pack the sauce separately',
        ),
      ],
    );
    return VendorOrdersPage(items: [order], total: 1, page: page, limit: limit);
  }

  @override
  Future<VendorMetrics> fetchMetrics({DateTime? from, DateTime? to, required String token}) async {
    return VendorMetrics(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 1, 31),
      totalOrders: 128,
      totalRevenueKobo: 45000000,
      mostOrderedItems: const [
        VendorMetricsItem(name: 'Special Jollof Rice with Grilled Chicken and Fried Plantain', count: 64, revenueKobo: 22400000),
        VendorMetricsItem(name: 'Suya', count: 12, revenueKobo: 3600000),
      ],
    );
  }

  // Task 14: the same "deliberately long real-shaped data" convention,
  // extended to the student-side vendor/menu browsing this task adds —
  // long business names/categories/descriptions are exactly what a real
  // (if verbose) vendor sign-up could produce.
  static const _longVendor = MyVendorProfile(
    id: 'vendor-long',
    businessName: 'Mama Kemi\'s Authentic Nigerian Kitchen and Grill House',
    category: 'Nigerian Continental Cuisine',
    description: 'Home-style jollof, native soups, grills, and fresh juices — made to order, every day of the week.',
  );

  @override
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20}) async {
    return const VendorsPage(
      items: [
        _longVendor,
        MyVendorProfile(id: 'vendor-short', businessName: 'Suya Spot', category: 'Grills'),
      ],
      total: 2,
      page: 1,
      limit: 20,
    );
  }

  @override
  Future<VendorWithMenu> fetchMenu(String vendorId) async {
    return const VendorWithMenu(
      vendor: _longVendor,
      items: [
        VendorMenuItem(
          id: 'item-long',
          name: 'Special Jollof Rice with Grilled Chicken, Fried Plantain, and Coleslaw',
          description: 'Smoky party-style jollof rice, char-grilled chicken thigh, sweet plantain, and a side of coleslaw.',
          priceKobo: 450000,
          category: 'Combo Meals',
          isAvailable: true,
        ),
        VendorMenuItem(
          id: 'item-soldout',
          name: 'Chef\'s Special Seafood Okra Soup with Assorted Meat',
          priceKobo: 500000,
          category: 'Soups',
          isAvailable: false,
        ),
      ],
    );
  }
}

AuthSession _sessionFor(AccountType accountType) => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: '${accountType.name}-1',
    name: 'Test ${accountType.name}',
    contact: '${accountType.name}@campus.edu',
    accountType: accountType,
    campusId: 'ui',
  ),
);

void main() {
  group('Home screen at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        final router = GoRouter(
          initialLocation: AppRoutes.home,
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (_, _) => const HomeScreen(),
            ),
            GoRoute(
              path: AppRoutes.menu,
              builder: (_, _) => const SizedBox.shrink(),
            ),
            GoRoute(
              path: AppRoutes.studentProfile,
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_sessionFor(AccountType.student)),
              ),
              // Task 14: Home's "Popular around campus" + category chips
              // now fetch real vendor data — seeded here with a
              // deliberately long business name/category/description
              // rather than the short mock strings the old hardcoded card
              // list used.
              vendorsRepositoryProvider.overrideWithValue(
                const _ScaleTestVendorsRepository(),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, widget) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: widget!,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Student + Runner nav shell at Dynamic Type scale', () {
    for (final scale in _scales) {
      for (final role in AppRole.values) {
        testWidgets(
          '$role nav shell renders with no overflow at ${scale}x text scale',
          (tester) async {
            final route = role == AppRole.student
                ? AppRoutes.home
                : AppRoutes.runnerHome;
            final router = GoRouter(
              initialLocation: route,
              routes: [
                GoRoute(
                  path: route,
                  builder: (_, _) =>
                      AppNavShell(role: role, child: const SizedBox.shrink()),
                ),
              ],
            );
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  authControllerProvider.overrideWith(
                    () => _FakeAuthController(
                      _sessionFor(
                        role == AppRole.student
                            ? AccountType.student
                            : AccountType.runner,
                      ),
                    ),
                  ),
                ],
                child: MaterialApp.router(
                  routerConfig: router,
                  builder: (context, widget) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: widget!,
                  ),
                ),
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));

            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  group('Eatery menu screen (vendor hero card) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            const EateryMenuScreen(vendorId: 'vendor-long'),
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_sessionFor(AccountType.student)),
              ),
              // Task 14: real vendor/menu data (long name, long item name,
              // and a sold-out item's greyed-out state) rather than the
              // old mock's short fixed strings.
              vendorsRepositoryProvider.overrideWithValue(
                const _ScaleTestVendorsRepository(),
              ),
            ],
          ),
        );
        await tester.pump();
        // Lets the eatery + menu FutureProviders resolve.
        await tester.pump(const Duration(milliseconds: 1200));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Item Options sheet (long name + note field) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        // The sheet itself is a private widget of ordering_screens.dart —
        // reached the same way a real student reaches it: tapping an
        // available menu item's row on the real EateryMenuScreen.
        await tester.pumpWidget(
          _atScale(
            scale,
            const EateryMenuScreen(vendorId: 'vendor-long'),
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_sessionFor(AccountType.student)),
              ),
              vendorsRepositoryProvider.overrideWithValue(
                const _ScaleTestVendorsRepository(),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1200));

        final itemFinder = find.text('Special Jollof Rice with Grilled Chicken, Fried Plantain, and Coleslaw');
        await tester.ensureVisible(itemFinder);
        await tester.pumpAndSettle();
        await tester.tap(itemFinder);
        await tester.pumpAndSettle();
        // Types a note long enough to have overflowed the old fixed-line
        // layout before AppTextField grew a real maxLines/maxLength.
        await tester.enterText(
          find.byType(TextField).last,
          'Please make it extra spicy, no onions at all, and pack the stew separately from the rice',
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CampusPickerField (long campus name) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: CampusPickerField(
                  selected: const Campus(
                    id: 'long',
                    name: 'Obafemi Awolowo University — Main Campus, Ile-Ife',
                    latitude: 7.5181,
                    longitude: 4.5284,
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('BankPickerField (long bank name) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: BankPickerField(
                  selected: const Bank(
                    name: 'Guaranty Trust Bank (Nigeria) Limited — Corporate Division',
                    code: '058',
                  ),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CategoryPickerField (long category label) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: CategoryPickerField(
                  selected: 'Nigerian Continental Fusion & Fine Dining Cuisine',
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('PayoutAccountForm (editable state) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: PayoutAccountForm(onSaved: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        // Lets the (network-backed) banksProvider settle into its error
        // state in this offline test environment.
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('WelcomeBackScreen at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            const WelcomeBackScreen(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50)); // biometric probe

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('RestaurantOrdersScreen order card (long id/name/note) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            const RestaurantOrdersScreen(),
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_restaurantSessionForScale()),
              ),
              vendorsRepositoryProvider.overrideWithValue(
                const _ScaleTestVendorsRepository(),
              ),
            ],
          ),
        );
        await tester.pump();
        // A second, timed pump so the resolved fetch replaces the
        // shimmering skeleton before the test ends (see Task 12's own
        // "Timer is still pending" gotcha).
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('RestaurantMetricsScreen range chips (long ranked item name) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            const RestaurantMetricsScreen(),
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_restaurantSessionForScale()),
              ),
              vendorsRepositoryProvider.overrideWithValue(
                const _ScaleTestVendorsRepository(),
              ),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('PrimaryButton (long dynamic label) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        await tester.pumpWidget(
          _atScale(
            scale,
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                // Mirrors the app's own longest dynamically-built labels
                // (e.g. the floating basket bar's "View Basket · N items
                // · ₦total").
                child: PrimaryButton(
                  label: 'View Basket · 12 items · ₦125,000',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Rating prompt (Task 14 Part D, long comment) at Dynamic Type scale', () {
    for (final scale in _scales) {
      testWidgets('renders with no overflow at ${scale}x text scale', (
        tester,
      ) async {
        // The default test surface is too short for this screen's own
        // scrollable content to actually inflate elements past the
        // confirm button (SliverList only builds within its cache
        // extent) — a realistic phone viewport, same convention as
        // order_tracking_lifecycle_test.dart.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _atScale(
            scale,
            const OrderTrackingScreen(),
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_sessionFor(AccountType.student)),
              ),
            ],
          ),
        );
        final element = tester.element(find.byType(OrderTrackingScreen));
        final container = ProviderScope.containerOf(element);
        container
            .read(orderTrackingProvider.notifier)
            .placeOrder(
              orderId: 'order-scale-1',
              orderItems: const ['1 × Jollof'],
              total: 3000,
              eateryName: 'Tantalizers',
              deliveryLocationLabel: 'Hostel B',
            );
        container.read(orderTrackingProvider.notifier)
          ..advanceForTest()
          ..markPickedUp()
          ..markDelivered();
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text("I've received my order"), 200);
        await tester.pumpAndSettle();
        await tester.tap(find.text("I've received my order"));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.star_border_rounded).first);
        await tester.pump();
        await tester.enterText(
          find.byType(TextField).last,
          'Everything arrived warm and on time, the runner was polite and communicative throughout',
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  });
}
