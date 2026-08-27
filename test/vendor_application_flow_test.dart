import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/vendor/application/vendor_application_controller.dart';
import 'package:run_it/features/vendor/domain/vendor_models.dart';
import 'package:run_it/features/vendor/presentation/vendor_application_screen.dart';
import 'package:run_it/features/vendor/presentation/vendor_pending_screen.dart';

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
      'a returning restaurant account lands on the vendor pending screen',
      () {
        const user = UserProfile(
          id: 'vendor-1',
          name: 'Kemi Adebayo',
          contact: '+2348012345678',
          accountType: AccountType.restaurant,
          campusId: 'ui',
        );
        expect(postAuthDestination(user), AppRoutes.vendorPending);
      },
    );
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
            path: AppRoutes.vendorPending,
            builder: (_, _) => const VendorPendingScreen(),
          ),
        ],
      );
      return ProviderScope(child: MaterialApp.router(routerConfig: router));
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
        await tester.tap(find.text('Nigerian'));
        await tester.pump();
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
        await tester.pump();

        // Step 3 — Review: every value shown must be exactly what was
        // entered, not a placeholder/relabeled copy.
        expect(find.text("Mama Kemi's Kitchen"), findsOneWidget);
        expect(find.text('Nigerian'), findsOneWidget);
        expect(find.text('Kemi Adebayo'), findsOneWidget);
        expect(find.textContaining('08012345678'), findsOneWidget);
        expect(find.text('University of Ibadan'), findsOneWidget);

        final container = ProviderScope.containerOf(
          tester.element(find.byType(VendorApplicationScreen)),
        );
        expect(
          container.read(vendorApplicationProvider).status,
          VendorApplicationStatus.draft,
        );

        await tester.ensureVisible(find.text('Submit for Review'));
        await tester.pump();
        await tester.tap(find.text('Submit for Review'));
        // Not pumpAndSettle: the Pending screen's RadarPulse repeats
        // forever by design, so settling would never terminate.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        // STUB submission: a local pending-state record, and the hand-off
        // to the Pending screen — no real backend call.
        expect(
          container.read(vendorApplicationProvider).status,
          VendorApplicationStatus.pending,
        );
        expect(find.text('Application submitted'), findsOneWidget);
        expect(find.textContaining("Mama Kemi's Kitchen"), findsWidgets);
      },
    );
  });
}
