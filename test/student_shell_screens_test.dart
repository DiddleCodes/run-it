import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:run_it/core/network/vendors_repository.dart';
import 'package:run_it/core/routing/app_router.dart';
import 'package:run_it/core/widgets/app_nav_shell.dart';
import 'package:run_it/core/widgets/app_notification.dart';
import 'package:run_it/core/widgets/primary_button.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/home/presentation/home_screen.dart';
import 'package:run_it/features/ordering/application/ordering_providers.dart';
import 'package:run_it/features/ordering/domain/ordering_models.dart';
import 'package:run_it/features/ordering/presentation/my_orders_screen.dart';
import 'package:run_it/features/payout/application/payout_controller.dart';
import 'package:run_it/features/payout/domain/payout_models.dart';
import 'package:run_it/features/profile/presentation/student_profile_screen.dart';
import 'package:run_it/features/vendor/domain/vendor_dashboard_models.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';
import 'package:run_it/features/wallet/data/wallet_repository.dart';
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

/// Task 32: no payout account on file — the real "add a bank account
/// first" branch of Withdraw. `.load()` is a real repository call in
/// production (PayoutController) — overridden here so this test never
/// hits the network.
class _NoPayoutAccountController extends PayoutController {
  @override
  PayoutAccount? build() => null;

  @override
  Future<void> load() async {}
}

const _savedPayoutAccount = PayoutAccount(
  bankCode: '058',
  bankName: 'GTBank',
  accountNumber: '0123456789',
  accountName: 'Ayanfe O.',
);

class _SavedPayoutAccountController extends PayoutController {
  @override
  PayoutAccount? build() => _savedPayoutAccount;

  @override
  Future<void> load() async {}
}

/// Task 32: stands in for the real `POST /wallet/withdraw/initiate` +
/// polling round-trip — resolves to 'success' on the very first poll tick
/// so these tests don't need to wait out the real ~40s polling window.
class _SucceedingWithdrawalRepository extends WalletRepository {
  _SucceedingWithdrawalRepository();
  String? capturedUserId;
  int? capturedAmountNaira;

  @override
  Future<WalletWithdrawalResult> initiateWithdrawal({
    required String userId,
    required int amountNaira,
    required String token,
  }) async {
    capturedUserId = userId;
    capturedAmountNaira = amountNaira;
    return const WalletWithdrawalResult(id: 'wt-1', status: 'pending');
  }

  @override
  Future<List<WalletTransaction>> getTransactions({required String userId, required String token}) async {
    return [
      WalletTransaction(
        id: 'wt-1',
        title: 'Withdrawal',
        subtitle: 'To your bank account',
        amount: 500,
        kind: WalletTransactionKind.debit,
        occurredAt: DateTime.now(),
        status: 'success',
      ),
    ];
  }
}

class _FailingWithdrawalRepository extends WalletRepository {
  const _FailingWithdrawalRepository();

  @override
  Future<WalletWithdrawalResult> initiateWithdrawal({
    required String userId,
    required int amountNaira,
    required String token,
  }) async {
    return const WalletWithdrawalResult(id: 'wt-2', status: 'pending');
  }

  @override
  Future<List<WalletTransaction>> getTransactions({required String userId, required String token}) async {
    return [
      WalletTransaction(
        id: 'wt-2',
        title: 'Withdrawal',
        subtitle: 'To your bank account',
        amount: 500,
        kind: WalletTransactionKind.debit,
        occurredAt: DateTime.now(),
        status: 'failed',
      ),
    ];
  }
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
      'Withdraw with no bank account on file prompts to add one instead of showing an amount form',
      (tester) async {
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
              payoutControllerProvider.overrideWith(() => _NoPayoutAccountController()),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        expect(find.text('Add a bank account to withdraw'), findsOneWidget);
        expect(find.text('Add bank account'), findsOneWidget);
        // No amount chips shown until a bank account exists.
        expect(find.text('₦500'), findsNothing);
      },
    );

    testWidgets(
      'a real withdrawal debits the amount, shows the confirmed real bank account, and settles to a real success state',
      (tester) async {
        final repository = _SucceedingWithdrawalRepository();
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
              payoutControllerProvider.overrideWith(() => _SavedPayoutAccountController()),
              walletRepositoryProvider.overrideWithValue(repository),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        // The real confirmed account is shown, not a stub message.
        expect(find.text('Sent to •••• 6789 — GTBank.'), findsOneWidget);

        await tester.tap(find.text('₦500'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('walletAmountSheetConfirm')));
        await tester.pump(); // launchingCheckout
        await tester.pump(const Duration(seconds: 3)); // poll tick fires
        await tester.pump();

        expect(repository.capturedUserId, 'student-1');
        expect(repository.capturedAmountNaira, 500);
        expect(find.text('₦500 withdrawn'), findsOneWidget);
      },
    );

    testWidgets(
      'a withdrawal that Paystack rejects shows that the money was already returned, not a bare failure',
      (tester) async {
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
              payoutControllerProvider.overrideWith(() => _SavedPayoutAccountController()),
              walletRepositoryProvider.overrideWithValue(const _FailingWithdrawalRepository()),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('₦500'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('walletAmountSheetConfirm')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();

        expect(find.text('Withdrawal failed'), findsOneWidget);
        expect(find.textContaining('is back in your wallet'), findsOneWidget);
      },
    );

    testWidgets(
      'Withdraw blocks an amount larger than the real balance before ever calling the backend',
      (tester) async {
        final repository = _SucceedingWithdrawalRepository();
        await tester.pumpWidget(
          _withStudentSession(
            const WalletScreen(),
            extraOverrides: [
              walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()), // 8450
              walletTransactionsProvider.overrideWith(() => _EmptyWalletTransactions()),
              payoutControllerProvider.overrideWith(() => _SavedPayoutAccountController()),
              walletRepositoryProvider.overrideWithValue(repository),
            ],
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Withdraw'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '20000');
        await tester.pump();

        expect(find.text("That's more than your ₦8450 balance."), findsOneWidget);
        final button = tester.widget<PrimaryButton>(find.byKey(const Key('walletAmountSheetConfirm')));
        expect(button.onPressed, isNull);
        expect(repository.capturedAmountNaira, isNull);
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

    // Task 38: the bell used to carry a hardcoded `badge: true` red dot
    // with no real unread-tracking behind it — the same fake-badge bug
    // Task 22 already fixed on the Home screen, just missed here.
    testWidgets('bell shows no fake unread badge, and tapping it is an honest "coming soon"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _withStudentSession(const StudentProfileScreen()),
      );
      await tester.pump();

      final bellButton = find.ancestor(
        of: find.byIcon(CupertinoIcons.bell),
        matching: find.byType(InkWell),
      );
      expect(bellButton, findsOneWidget);
      // A `Positioned` badge dot was the only reason this button's tree
      // ever contained a Positioned widget — asserting none exist here
      // is a direct, load-bearing check against the fake-badge regression.
      expect(find.descendant(of: bellButton, matching: find.byType(Positioned)), findsNothing);

      await tester.tap(find.byIcon(CupertinoIcons.bell));
      await tester.pump();
      expect(find.text('Notifications are coming soon.'), findsOneWidget);
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
