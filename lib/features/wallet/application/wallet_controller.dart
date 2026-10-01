import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cached_fetch.dart';
import '../../../core/cache/cached_sources.dart';
import '../../auth/application/auth_controller.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet_models.dart';

/// The signed-in user's real RUN-It Wallet balance (Task 8d; runner-usable
/// since Task 33, once delivery earnings start crediting it) — backed by
/// the Task 8b payments backend's ledger, not local mock state. `null`
/// session (not yet signed in) resolves to 0 rather than an error; there's
/// nothing to fetch yet.
/// Naira, kobo included (₦1,444.50 is 1444.5).
class WalletBalanceController extends AsyncNotifier<num> {
  @override
  Future<num> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null) return 0;
    ref.watch(walletRepositoryProvider);
    return cachedFetch<num>(ref, walletBalanceSource(ref, session));
  }

  /// Re-fetches from the backend and waits for the new value — used after
  /// a top-up so the caller can read the real, settled balance rather than
  /// guessing at what it should now be.
  Future<num> refresh() async {
    final session = ref.read(authControllerProvider);
    if (session != null) ref.read(cacheSessionProvider).forceNetwork(CacheKeys.wallet(session.user.id));
    ref.invalidateSelf();
    return future;
  }
}

final walletBalanceProvider = AsyncNotifierProvider<WalletBalanceController, num>(
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
