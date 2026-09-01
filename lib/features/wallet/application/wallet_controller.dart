import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_models.dart';

/// The signed-in student's real RUN-It Wallet balance (Task 8d) — backed by
/// the Task 8b payments backend's ledger, not local mock state. `null`
/// session (not yet signed in) resolves to 0 rather than an error; there's
/// nothing to fetch yet.
class WalletBalanceController extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null) return 0;
    final repository = ref.watch(walletRepositoryProvider);
    return repository.getBalance(userId: session.user.id, token: session.accessToken);
  }

  /// Re-fetches from the backend and waits for the new value — used after
  /// a top-up so the caller can read the real, settled balance rather than
  /// guessing at what it should now be.
  Future<int> refresh() async {
    ref.invalidateSelf();
    return future;
  }
}

final walletBalanceProvider = AsyncNotifierProvider<WalletBalanceController, int>(
  WalletBalanceController.new,
);

/// The Wallet screen's "Recent transactions" list — real ledger rows from
/// the backend (Task 8d), replacing the local/demo feed Task 5 shipped.
class WalletTransactionsController extends AsyncNotifier<List<WalletTransaction>> {
  @override
  Future<List<WalletTransaction>> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null) return const [];
    final repository = ref.watch(walletRepositoryProvider);
    return repository.getTransactions(userId: session.user.id, token: session.accessToken);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final walletTransactionsProvider =
    AsyncNotifierProvider<WalletTransactionsController, List<WalletTransaction>>(
      WalletTransactionsController.new,
    );
