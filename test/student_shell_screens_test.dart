import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_nav_shell.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/profile/presentation/student_profile_screen.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';
import 'package:run_it/features/wallet/domain/wallet_models.dart';
import 'package:run_it/features/wallet/presentation/wallet_screen.dart';

class _FixedBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 8450;
}

class _EmptyWalletTransactions extends WalletTransactionsController {
  @override
  Future<List<WalletTransaction>> build() async => const [];
}

/// Task 14: Home now fetches real vendor data (`GET /vendors`) instead of
/// its old hardcoded card list — this fake keeps the Home-screen test
/// network-free. Empty is a fine default here: the test only asserts on
/// the always-static Campus Pick card, not the vendor list.
class _FakeVendorsRepository extends VendorsRepository {
  const _FakeVendorsRepository();
  @override
  Future<VendorsPage> listVendors({String? category, String? search, int page = 1, int limit = 20}) async =>
      VendorsPage(items: const [], total: 0, page: page, limit: limit);
}

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

AuthSession _runnerSession() => AuthSession(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 5)),
  user: const UserProfile(
    id: 'runner-1',
    name: 'Ada Runner',
    contact: '+2348000000000',
    accountType: AccountType.runner,
    campusId: 'ui',
    kycStatus: KycStatus.verified,
    runnerType: RunnerType.studentRunner,
  ),
);

Widget _withStudentSession(
  Widget child, {
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(
        () => _FakeAuthController(_studentSession()),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      home: child,
      builder: (context, widget) =>
          AppNotificationHost(child: widget ?? const SizedBox.shrink()),
    ),
  );
}

void main() {
  group('AppNavShell is parameterized by role', () {
    testWidgets(
      'student role shows a basket FAB with a badge when the basket is non-empty',
      (tester) async {
        final router = GoRouter(
          initialLocation: AppRoutes.home,
          routes: [
            GoRoute(
              path: AppRoutes.home,
              builder: (context, state) => const AppNavShell(
                role: AppRole.student,
                child: SizedBox.shrink(),
              ),
            ),
          ],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(
                () => _FakeAuthController(_studentSession()),
              ),
              basketProvider.overrideWith(() => _NonEmptyBasketNotifier()),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byIcon(CupertinoIcons.bag_fill), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.viewfinder), findsNothing);
        expect(find.text('3'), findsOneWidget); // the mock basket's item count
        expect(find.text('Basket'), findsOneWidget);
        expect(find.text('Orders'), findsOneWidget);
        expect(find.text('Wallet'), findsOneWidget);
      },
    );

    testWidgets('runner role shows a scan FAB with no badge', (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.runnerHome,
        routes: [
          GoRoute(
            path: AppRoutes.runnerHome,
            builder: (context, state) => const AppNavShell(
              role: AppRole.runner,
              child: SizedBox.shrink(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => _FakeAuthController(_runnerSession()),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(CupertinoIcons.viewfinder), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.bag_fill), findsNothing);
      expect(find.text('Jobs'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
    });
  });

  group('Home screen', () {
    testWidgets('renders the fixed Campus Pick card with no layout overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _withStudentSession(
          const HomeScreen(),
          extraOverrides: [vendorsRepositoryProvider.overrideWithValue(const _FakeVendorsRepository())],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(tester.takeException(), isNull);
      expect(find.text('CAMPUS PICK'), findsOneWidget);
      expect(find.text('Order Now'), findsOneWidget);
      expect(find.text('What are you\ncraving today?'), findsOneWidget);
    });
  });

  group('My Orders screen', () {
    testWidgets(
      'defaults to Active tab; shows the empty state with no active order',
      (tester) async {
        await tester.pumpWidget(_withStudentSession(const MyOrdersScreen()));
        await tester.pump();

        expect(find.text('Active (0)'), findsOneWidget);
        expect(find.text('No active order'), findsOneWidget);

        await tester.tap(find.text('Past'));
        await tester.pump();
        expect(find.text('Tantalizers'), findsOneWidget);
        expect(find.text('Reorder'), findsWidgets);

        await tester.tap(find.text('Cancelled'));
        await tester.pump();
        expect(find.text('No cancelled orders'), findsOneWidget);
      },
    );
  });

  group('Wallet screen', () {
    testWidgets(
      'shows the real fetched balance (Task 8d), not a fabricated local starting value',
      (tester) async {
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('₦8450'), findsOneWidget);

        await tester.tap(find.text('Add Funds').first);
        await tester.pumpAndSettle();

        final sheet = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_AmountSheet',
        );
        expect(sheet, findsOneWidget);
        // The sheet now points at the real Paystack checkout, not the old
        // "this is a stub" copy.
        expect(find.text('Pay securely with Paystack.'), findsOneWidget);
        expect(find.textContaining('stub'), findsNothing);
      },
    );

    testWidgets(
      'Withdraw is honestly stubbed — no backend student-payout endpoint exists yet',
      (tester) async {
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('₦500'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          find.textContaining("Withdrawals aren't available yet"),
          findsWidgets,
        );
        // The balance never silently changed under a fake local withdrawal.
        expect(find.text('₦8450'), findsOneWidget);
      },
    );
  });

  group('Profile screen', () {
    testWidgets('shows the student identity card and RUN-It Plus banner', (
      tester,
    ) async {
      await tester.pumpWidget(
        _withStudentSession(const StudentProfileScreen()),
      );
      await tester.pump();

      expect(find.text('Ayanfe O.'), findsOneWidget);
      expect(find.text('ayanfe@student.ui.edu.ng'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('RUN-It Plus'), findsOneWidget);
    });
  });
}

/// A basket seeded with 3 items across 2 lines, purely to exercise the
/// nav shell's basket badge — the notifier's own add/remove logic isn't
/// under test here.
class _NonEmptyBasketNotifier extends BasketNotifier {
  @override
  Basket build() => const Basket(
    eateryId: 'e1',
    items: [
      BasketItem(menuItemId: 'm1', quantity: 2),
      BasketItem(menuItemId: 'm2', quantity: 1),
    ],
  );
}
