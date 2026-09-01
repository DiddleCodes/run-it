import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/ratings_repository.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/runner/domain/runner_models.dart';
import 'package:run_it/features/runner/presentation/runner_jobs_screen.dart';
import 'package:run_it/features/runner/presentation/runner_messages_screen.dart';
import 'package:run_it/features/runner/presentation/runner_profile_screen.dart';
import 'package:run_it/features/runner/presentation/runner_scan_screen.dart';
import 'package:run_it/features/runner/presentation/runner_screens.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession _session;
  @override
  AuthSession? build() => _session;
}

AuthSession _runnerSession({
  required RunnerType runnerType,
  KycStatus kycStatus = KycStatus.verified,
}) => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: UserProfile(
    id: 'runner-1',
    name: 'Ada Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: kycStatus,
    runnerType: runnerType,
  ),
);

/// Task 14: `RunnerJobsScreen`'s Available tab now draws its job previews
/// from real vendor data (`campusEateriesProvider`, `GET /vendors`)
/// instead of the old `MockOrderingRepository`'s fixed "Tantalizers" entry
/// — this fake keeps that same name so the test's own assertions don't
/// need to change, while keeping the test network-free.
class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository();
  @override
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20}) async {
    return const VendorsPage(
      items: [MyVendorProfile(id: 'tantalizers', businessName: 'Tantalizers', category: 'Meals')],
      total: 1,
      page: 1,
      limit: 20,
    );
  }
}

/// Task 14: Runner Profile now fetches its real rating aggregate — a fixed
/// stub keeps these unrelated tests network-free.
class _FakeRatingsRepository extends RatingsRepository {
  const _FakeRatingsRepository();
  @override
  Future<RunnerRatingSummary> fetchRunnerRatingSummary(String runnerId) async =>
      RunnerRatingSummary(runnerId: runnerId, averageRating: 4.8, ratingCount: 12);
}

DeliveryJob _job() => DeliveryJob(
  id: 'job-1',
  campusId: 'ui',
  eateryName: 'Jollof Palace',
  eateryLocation: 'Student Centre',
  dropoffZone: 'Hostel B, Room 204',
  dropoffLocation: 'Room 204',
  payoutAmount: 800,
  estimatedDistanceMeters: 500,
  offeredAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(seconds: 20)),
);

void main() {
  group('scanContextFor — Scan screen context-bar logic', () {
    test('an accepted (not yet picked up) delivery asks for the pickup code', () {
      final active = ActiveDelivery(
        job: _job(),
        status: DeliveryStage.accepted,
        orderNumber: '#RI-1',
        orderItems: const [],
      );
      final ctx = scanContextFor(active);
      expect(ctx.label, 'Scanning pickup code');
      expect(ctx.subject, 'Jollof Palace');
    });

    test('a picked-up delivery asks for the delivery code instead', () {
      final active = ActiveDelivery(
        job: _job(),
        status: DeliveryStage.pickedUp,
        orderNumber: '#RI-1',
        orderItems: const [],
      );
      final ctx = scanContextFor(active);
      expect(ctx.label, 'Scanning delivery code');
      expect(ctx.subject, 'Hostel B, Room 204');
    });
  });

  testWidgets('Scan screen shows an empty state with no active delivery', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
          ),
        ],
        child: const MaterialApp(home: RunnerScanScreen()),
      ),
    );
    await tester.pump();

    // No active delivery — the generic fallback prompt, not a
    // context-blind label, and not an error from mounting the camera
    // widget without a real platform channel.
    expect(find.text('Scan to start or complete a delivery'), findsOneWidget);
  });

  testWidgets('Jobs screen defaults to the Available tab with all 3 segments', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
          ),
          vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
        ],
        child: const MaterialApp(home: RunnerJobsScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Available'), findsOneWidget);
    expect(find.text('Accepted'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    // The mock ordering repository has exactly one eatery on campus 'ui'.
    expect(find.text('Tantalizers'), findsOneWidget);

    await tester.tap(find.text('Accepted'));
    await tester.pump();
    expect(find.text('No active job'), findsOneWidget);

    await tester.tap(find.text('Completed'));
    await tester.pump();
    expect(find.text('No completed deliveries yet'), findsOneWidget);

    // Let the Available tab's card entrance-animation timer (flutter_animate)
    // resolve before teardown — an unresolved Timer fails the test even
    // though it has no bearing on the behavior under test.
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Messages screen pins RUN-It Support at the top', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
          ),
        ],
        child: const MaterialApp(home: RunnerMessagesScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('RUN-It Support'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.shield_fill), findsOneWidget);

    final supportY = tester.getTopLeft(find.text('RUN-It Support')).dy;
    final otherThreadY = tester.getTopLeft(find.text('Tantalizers')).dy;
    expect(supportY, lessThan(otherThreadY));
  });

  group('Profile screen', () {
    testWidgets('shows the runner\'s name and KYC status, no Vehicle section for a student runner', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
            ),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
          ],
          child: const MaterialApp(home: RunnerProfileScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Ada Runner'), findsOneWidget);
      expect(find.text('Student Runner'), findsOneWidget);
      expect(find.text('Verification'), findsOneWidget);
      expect(find.text('Vehicle / Mode'), findsNothing);
    });

    testWidgets('shows a Vehicle Info section for an independent rider', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _runnerSession(runnerType: RunnerType.independentRider),
              ),
            ),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
          ],
          child: const MaterialApp(home: RunnerProfileScreen()),
        ),
      );
      await tester.pump();

      expect(find.text('Independent Rider'), findsOneWidget);
      expect(find.text('Vehicle / Mode'), findsOneWidget);
    });
  });

  group('icon sourcing — no low-res PNG stands in for a mandated SF Symbol', () {
    testWidgets('the bottom nav renders every icon as a vector Icon, never an Image', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: AppRoutes.runnerHome,
        routes: [
          GoRoute(
            path: AppRoutes.runnerHome,
            builder: (context, state) => const RunnerShell(child: RunnerHomeScreen()),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(CupertinoIcons.house_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.bag), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.viewfinder), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chat_bubble), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.person), findsOneWidget);

      // Scoped to the nav bar itself, not the whole screen — the
      // dashboard's own header legitimately uses a decorative PNG
      // (route_decoration.png), which the icon-sourcing rule explicitly
      // allows for hero/illustration art. It's the nav bar's *icons*
      // that must never fall back to a raster asset.
      final navBar = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_AppNavBar',
      );
      expect(navBar, findsOneWidget);
      expect(find.descendant(of: navBar, matching: find.byType(Image)), findsNothing);
    });

    testWidgets('Jobs, Messages, and Profile headers render vector icons, never an Image', (
      tester,
    ) async {
      for (final screen in [
        const RunnerJobsScreen(),
        const RunnerMessagesScreen(),
        const RunnerProfileScreen(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_runnerSession(runnerType: RunnerType.studentRunner)),
              ),
              vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
              ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
            ],
            child: MaterialApp(home: screen),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(Image), findsNothing, reason: '${screen.runtimeType} rendered an Image');
      }
    });
  });

  group('TASK 4g §1 — pending-KYC runners keep limited, read-only access', () {
    testWidgets('Jobs screen shows a read-only banner and no Accept button', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _runnerSession(
                  runnerType: RunnerType.studentRunner,
                  kycStatus: KycStatus.pending,
                ),
              ),
            ),
            vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository()),
          ],
          child: const MaterialApp(home: RunnerJobsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.textContaining("browsing read-only while your ID is under review"),
        findsOneWidget,
      );
      expect(find.text('Accept Job'), findsNothing);
      expect(find.text('Pending verification'), findsWidgets);

      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Profile screen shows a Pending review card, not a blocked screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(
                _runnerSession(
                  runnerType: RunnerType.studentRunner,
                  kycStatus: KycStatus.pending,
                ),
              ),
            ),
            ratingsRepositoryProvider.overrideWithValue(const _FakeRatingsRepository()),
          ],
          child: const MaterialApp(home: RunnerProfileScreen()),
        ),
      );
      await tester.pump();

      // Still a fully-rendered, real Profile — not a redirect/blank screen.
      expect(find.text('Ada Runner'), findsOneWidget);
      expect(find.text('Verification pending review'), findsOneWidget);
    });
  });
}
