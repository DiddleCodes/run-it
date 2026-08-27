import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/wallet_models.dart';

/// The signed-in student's RUN-It Wallet balance, in naira. Started life as
/// a fixed `Provider<int>` in `ordering_providers.dart` (Checkout just
/// read it to check "can this cover the order"); moved here and upgraded
/// to a real [Notifier] so Add Funds / Withdraw can actually change it —
/// [CheckoutScreen] still reads the same value through this provider.
///
/// STUB: `mockAddFunds`/`mockWithdraw` only ever touch this local,
/// in-memory state — there is no real payment-gateway call here. Real
/// Paystack/Flutterwave integration is its own dedicated task; when that
/// lands, it should drive this same provider rather than introducing a
/// second balance.
class WalletBalanceController extends Notifier<int> {
  @override
  int build() => 8450; // ₦8,450 starting demo balance.

  void mockAddFunds(int amount) {
    if (amount <= 0) return;
    state = state + amount;
  }

  /// Returns false (and leaves the balance untouched) if [amount] exceeds
  /// the current balance — same "can't go negative" guarantee a real
  /// gateway would enforce.
  bool mockWithdraw(int amount) {
    if (amount <= 0 || amount > state) return false;
    state = state - amount;
    return true;
  }
}

final walletBalanceProvider = NotifierProvider<WalletBalanceController, int>(
  WalletBalanceController.new,
);

/// Local/demo transaction feed backing the Wallet screen's "Recent
/// transactions" list — see [WalletTransaction]. A mock Add Funds/Withdraw
/// prepends a matching row here so the screen feels alive without a real
/// ledger backend.
class WalletTransactionsController extends Notifier<List<WalletTransaction>> {
  @override
  List<WalletTransaction> build() {
    final now = DateTime.now();
    return [
      WalletTransaction(
        id: 'txn-1',
        title: 'Cafe One',
        subtitle: 'Food order',
        amount: 2500,
        kind: WalletTransactionKind.debit,
        occurredAt: now.subtract(const Duration(hours: 3)),
      ),
      WalletTransaction(
        id: 'txn-2',
        title: 'Top Up',
        subtitle: 'Bank transfer',
        amount: 5000,
        kind: WalletTransactionKind.credit,
        occurredAt: now.subtract(const Duration(days: 1)),
      ),
      WalletTransaction(
        id: 'txn-3',
        title: 'Tantalizers',
        subtitle: 'Food order',
        amount: 2300,
        kind: WalletTransactionKind.debit,
        occurredAt: now.subtract(const Duration(days: 1, hours: 4)),
      ),
      WalletTransaction(
        id: 'txn-4',
        title: 'Rewards',
        subtitle: 'Referral bonus',
        amount: 500,
        kind: WalletTransactionKind.credit,
        occurredAt: now.subtract(const Duration(days: 4)),
      ),
    ];
  }

  void recordMockTopUp(int amount) {
    state = [
      WalletTransaction(
        id: 'txn-${DateTime.now().microsecondsSinceEpoch}',
        title: 'Wallet top-up',
        subtitle: 'Added funds (stub)',
        amount: amount,
        kind: WalletTransactionKind.credit,
        occurredAt: DateTime.now(),
      ),
      ...state,
    ];
  }

  /// Prepends a debit row for a checkout payment — same stub convention as
  /// [recordMockTopUp]/[recordMockWithdrawal], just triggered from Checkout
  /// instead of the Wallet screen itself.
  void recordOrderPayment({required String eateryName, required int amount}) {
    state = [
      WalletTransaction(
        id: 'txn-${DateTime.now().microsecondsSinceEpoch}',
        title: eateryName,
        subtitle: 'Food order',
        amount: amount,
        kind: WalletTransactionKind.debit,
        occurredAt: DateTime.now(),
      ),
      ...state,
    ];
  }

  void recordMockWithdrawal(int amount) {
    state = [
      WalletTransaction(
        id: 'txn-${DateTime.now().microsecondsSinceEpoch}',
        title: 'Withdrawal',
        subtitle: 'Sent to bank (stub)',
        amount: amount,
        kind: WalletTransactionKind.debit,
        occurredAt: DateTime.now(),
      ),
      ...state,
    ];
  }
}

final walletTransactionsProvider =
    NotifierProvider<WalletTransactionsController, List<WalletTransaction>>(
      WalletTransactionsController.new,
    );
