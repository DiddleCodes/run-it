import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/orders_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_models.dart';

/// Task 47: a runner's real, running Pay on Delivery cash debt — backs the
/// Wallet screen's "cash owed to platform" card. `null` for a non-runner
/// session (nothing to show), never an error — this is purely additive
/// information on top of the wallet balance every account type already
/// sees.
class RunnerCashDebtController extends AsyncNotifier<CashDebtSummary?> {
  @override
  Future<CashDebtSummary?> build() async {
    final session = ref.watch(authControllerProvider);
    if (session == null || session.user.accountType != AccountType.runner) return null;
    final repository = ref.watch(ordersRepositoryProvider);
    return repository.fetchCashDebtSummary(token: session.accessToken);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

final runnerCashDebtProvider = AsyncNotifierProvider<RunnerCashDebtController, CashDebtSummary?>(
  RunnerCashDebtController.new,
);
