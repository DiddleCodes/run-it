import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:run_it/core/network/orders_repository.dart';
import 'package:run_it/features/auth/application/auth_controller.dart';
import 'package:run_it/features/auth/domain/auth_models.dart';
import 'package:run_it/features/wallet/application/wallet_controller.dart';
import 'package:run_it/features/wallet/domain/wallet_models.dart';
import 'package:run_it/features/wallet/presentation/wallet_screen.dart';

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._session);
  final AuthSession? _session;
  @override
  AuthSession? build() => _session;
}

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

class _FixedBalanceWallet extends WalletBalanceController {
  @override
  Future<int> build() async => 220000;
}

class _EmptyTransactions extends WalletTransactionsController {
  @override
  Future<List<WalletTransaction>> build() async => const [];
}

class _FakeOrdersRepository extends OrdersRepository {
  const _FakeOrdersRepository(this.summary);
  final CashDebtSummary summary;

  @override
  Future<CashDebtSummary> fetchCashDebtSummary({required String token}) async => summary;
}

Widget _harness({required AuthSession session, required CashDebtSummary summary}) => ProviderScope(
  overrides: [
    authControllerProvider.overrideWith(() => _FakeAuthController(session)),
    walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
    walletTransactionsProvider.overrideWith(() => _EmptyTransactions()),
    ordersRepositoryProvider.overrideWithValue(_FakeOrdersRepository(summary)),
  ],
  child: const MaterialApp(home: WalletScreen()),
);

void main() {
  testWidgets('Task 47: a runner with outstanding Pay on Delivery cash debt sees the real running total on their Wallet screen', (
    tester,
  ) async {
    final summary = CashDebtSummary(
      totalOwedKobo: 45000,
      debts: [
        CashDebtEntry(
          orderId: 'order-1',
          amountOwedKobo: 30000,
          amountCollectedKobo: 30000,
          status: 'pending',
          createdAt: DateTime.now(),
        ),
        CashDebtEntry(
          orderId: 'order-2',
          amountOwedKobo: 15000,
          amountCollectedKobo: 10000,
          status: 'disputed',
          createdAt: DateTime.now(),
        ),
      ],
    );
    await tester.pumpWidget(_harness(session: _runnerSession(), summary: summary));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('₦450 owed to RUN-It'), findsOneWidget);
  });

  testWidgets('shows nothing extra for a runner with no outstanding debt', (tester) async {
    await tester.pumpWidget(
      _harness(session: _runnerSession(), summary: const CashDebtSummary(totalOwedKobo: 0, debts: [])),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('owed to RUN-It'), findsNothing);
  });

  testWidgets('never fetches or shows a cash debt for a student session', (tester) async {
    var fetchCalled = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _FakeAuthController(_studentSession())),
          walletBalanceProvider.overrideWith(() => _FixedBalanceWallet()),
          walletTransactionsProvider.overrideWith(() => _EmptyTransactions()),
          ordersRepositoryProvider.overrideWithValue(
            _RecordingFetchOrdersRepository(() => fetchCalled = true),
          ),
        ],
        child: const MaterialApp(home: WalletScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fetchCalled, isFalse);
    expect(find.textContaining('owed to RUN-It'), findsNothing);
  });
}

class _RecordingFetchOrdersRepository extends OrdersRepository {
  const _RecordingFetchOrdersRepository(this.onFetch);
  final void Function() onFetch;

  @override
  Future<CashDebtSummary> fetchCashDebtSummary({required String token}) async {
    onFetch();
    return const CashDebtSummary(totalOwedKobo: 0, debts: []);
  }
}
