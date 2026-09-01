import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/api_exception.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/segmented_progress_bar.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/payout/application/payout_controller.dart';
import 'package:run_it/features/payout/domain/payout_models.dart';
import 'package:run_it/features/vendor/application/my_vendor_profile_controller.dart';
import 'package:run_it/features/vendor/application/vendor_application_controller.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/vendor/domain/vendor_models.dart';
import 'package:run_it/features/vendor/presentation/restaurant_profile_setup_screen.dart';
import 'package:run_it/features/vendor/presentation/vendor_application_screen.dart';

/// Stands in for the real backend `GET/POST /vendors/me` calls so
/// `RestaurantProfileSetupScreen` can be driven without a live server —
/// same "subclass the Notifier" convention as [_FakePayoutController]
/// below. Starts as though no real vendor row exists yet (a fresh 404),
/// exactly what a genuinely first-run restaurant would see.
class _FakeMyVendorProfileController extends MyVendorProfileController {
  @override
  Future<MyVendorProfile> build() async {
    throw const ApiException(404, 'Create your vendor profile first via POST /vendors/me');
  }

  @override
  Future<MyVendorProfile> save({
    required String businessName,
    required String category,
    String? description,
    String? logoUrl,
  }) async {
    final profile = MyVendorProfile(
      id: 'vendor-1',
      businessName: businessName,
      category: category,
      description: description,
      logoUrl: logoUrl,
    );
    state = AsyncValue.data(profile);
    return profile;
  }
}

/// Stands in for the real [PayoutController] so the wizard's Payout
/// Details step can be driven in a widget test without a live backend —
/// same "subclass the Notifier, override the bit that would otherwise hit
/// the network" convention as every other controller test in this app
/// (see `auth_controller_passcode_test.dart`). Returns a fixed resolved
/// name, exactly like a real `POST /payout-accounts` success would.
class _FakePayoutController extends PayoutController {
  @override
  Future<List<Bank>> fetchBanks() async => const [Bank(name: 'GTBank', code: '058')];

  @override
  Future<PayoutAccount> verifyAndSave({
    required Bank bank,
    required String accountNumber,
  }) async {
    final account = PayoutAccount(
      bankCode: bank.code,
      bankName: bank.name,
      accountNumber: accountNumber,
      accountName: 'Kemi Adebayo',
    );
    state = account;
    return account;
  }
}

void main() {
  group('postBiometricDestination', () {
    test('restaurant routes to the vendor-application wizard, not Home or Runner Type', () {
      expect(
        postBiometricDestination(AccountType.restaurant),
        AppRoutes.vendorApplication,
      );
      expect(
        postBiometricDestination(AccountType.restaurant),
        isNot(AppRoutes.home),
      );
      expect(
        postBiometricDestination(AccountType.restaurant),
        isNot(AppRoutes.runnerType),
      );
    });

    test('student and runner destinations are unchanged', () {
      expect(postBiometricDestination(AccountType.student), AppRoutes.home);
      expect(
        postBiometricDestination(AccountType.runner),
        AppRoutes.runnerType,
      );
    });
  });

  group('postAuthDestination', () {
    test(
      'a returning restaurant account lands on profile setup, which self-checks the real backend',
      () {
        const user = UserProfile(
          id: 'vendor-1',
          name: 'Kemi Adebayo',
          contact: '+2348012345678',
          accountType: AccountType.restaurant,
          campusId: 'ui',
        );
        expect(postAuthDestination(user), AppRoutes.restaurantProfileSetup);
      },
    );
  });

  group('vendorSteps (dynamic step-count convention)', () {
    test('Payout Details is a real step, not a hardcoded literal elsewhere', () {
      expect(vendorSteps.length, 4);
      expect(vendorSteps, [
        VendorStepKind.businessInfo,
        VendorStepKind.contactLocation,
        VendorStepKind.payoutDetails,
        VendorStepKind.review,
      ]);
    });
  });

  group('Vendor application wizard', () {
    Widget buildApp() {
      final router = GoRouter(
        initialLocation: AppRoutes.vendorApplication,
        routes: [
          GoRoute(
            path: AppRoutes.vendorApplication,
            builder: (_, _) => const VendorApplicationScreen(),
          ),
          GoRoute(
            path: AppRoutes.restaurantProfileSetup,
            builder: (_, _) => const RestaurantProfileSetupScreen(),
          ),
          GoRoute(
            path: AppRoutes.restaurantOrders,
            builder: (_, _) => const Text('RESTAURANT_ORDERS'),
          ),
        ],
      );
      return ProviderScope(
        overrides: [
          payoutControllerProvider.overrideWith(() => _FakePayoutController()),
          myVendorProfileProvider.overrideWith(() => _FakeMyVendorProfileController()),
          // Task 15: category is now a picker fetched from the backend's
          // controlled vocabulary, not a fixed local enum.
          vendorCategoriesProvider.overrideWith(
            (ref) async => const [
              VendorCategoryOption(slug: 'nigerian', label: 'Nigerian'),
              VendorCategoryOption(slug: 'fast-food', label: 'Fast Food'),
            ],
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets(
      'Review screen accurately reflects entered data, and submitting produces a pending record',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pump();

        // Step 1 — Business Info.
        await tester.enterText(
          find.byType(TextField).first,
          "Mama Kemi's Kitchen",
        );
        await tester.tap(find.text('Choose a category'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nigerian'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pump();

        // Step 2 — Contact & Location.
        final contactFields = find.byType(TextField);
        await tester.enterText(contactFields.at(0), 'Kemi Adebayo');
        await tester.enterText(contactFields.at(1), '08012345678');
        await tester.tap(find.text('Choose your campus'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('University of Ibadan'));
        await tester.pumpAndSettle();
        // The storefront-photo capture box pushes Continue off the small
        // test viewport, inside the step's own scroll view.
        await tester.ensureVisible(find.text('Continue'));
        await tester.pump();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        // Step 3 — Payout Details: the progress bar must reflect all four
        // steps now, not the old hardcoded three.
        expect(
          tester.widget<SegmentedProgressBar>(find.byType(SegmentedProgressBar)).stepCount,
          vendorSteps.length,
        );
        expect(find.text('Payout details'), findsOneWidget);

        await tester.tap(find.text('Choose your bank'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('GTBank'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '0123456789');
        await tester.ensureVisible(find.text('Verify'));
        await tester.tap(find.text('Verify'));
        await tester.pump();
        await tester.pump();

        // The resolved name from the (fake) backend must show up for
        // confirmation before it's treated as saved.
        expect(find.text('Is this you?'), findsOneWidget);
        expect(find.text('Kemi Adebayo'), findsWidgets);
        await tester.tap(find.text("Yes, that's me"));
        await tester.pump();

        // Step 4 — Review: every value shown must be exactly what was
        // entered, not a placeholder/relabeled copy — including the
        // payout details just resolved.
        expect(find.text("Mama Kemi's Kitchen"), findsOneWidget);
        expect(find.text('Nigerian'), findsOneWidget);
        expect(find.text('Kemi Adebayo'), findsWidgets);
        expect(find.textContaining('08012345678'), findsOneWidget);
        expect(find.text('University of Ibadan'), findsOneWidget);
        expect(find.text('GTBank'), findsOneWidget);
        expect(find.textContaining('6789'), findsWidgets);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(VendorApplicationScreen)),
        );
        expect(
          container.read(vendorApplicationProvider).status,
          VendorApplicationStatus.draft,
        );

        await tester.ensureVisible(find.text('Submit'));
        await tester.pump();
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();

        // STUB submission: a local pending-state record — then straight
        // into Task 12's real profile-completion screen, auto-approved,
        // never the old dead-end Pending screen.
        expect(
          container.read(vendorApplicationProvider).status,
          VendorApplicationStatus.pending,
        );
        expect(find.text("You're approved!"), findsOneWidget);
        // Prefilled from the wizard's own data — never asks the restaurant
        // to re-enter what it already collected.
        expect(find.text("Mama Kemi's Kitchen"), findsOneWidget);
        expect(find.text('Nigerian'), findsOneWidget);

        // Confirming here is what actually replaces the backend's
        // auto-provisioned placeholder vendor with the real submitted
        // details (see VendorsService.upsertMyVendor's doc comment).
        await tester.ensureVisible(find.text('Get Started'));
        await tester.pump();
        await tester.tap(find.text('Get Started'));
        await tester.pumpAndSettle();

        expect(find.text('RESTAURANT_ORDERS'), findsOneWidget);
      },
    );
  });
}
