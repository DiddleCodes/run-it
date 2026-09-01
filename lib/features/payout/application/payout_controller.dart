import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/payout_repository.dart';
import '../domain/payout_models.dart';

/// The signed-in user's saved payout account, if any — null until [load]
/// resolves (or there genuinely isn't one yet). Shared by Runner Profile's
/// Payouts row (Task 8c Part B) and the vendor wizard's Payout Details step
/// (Part C) so both read/write through one source of truth instead of each
/// duplicating fetch/verify/save logic.
///
/// NOTE: [AuthSession.accessToken]/`user.id` are still the client-mocked
/// values [AuthRepository] fabricates today (see its doc comment) — this
/// controller sends them as-is. Once real OTP-issued JWTs land, the Bearer
/// header here starts carrying a real one with no change needed in this
/// file.
class PayoutController extends Notifier<PayoutAccount?> {
  final _repository = const PayoutRepository();

  @override
  PayoutAccount? build() => null;

  Future<List<Bank>> fetchBanks() {
    final session = ref.read(authControllerProvider);
    return _repository.fetchBanks(token: session?.accessToken ?? '');
  }

  /// Fetches the current user's saved account (if any), resolving its
  /// `bankCode` back to a display name from the same bank list the picker
  /// uses. Safe to call with no session (e.g. before login finishes) — it
  /// just no-ops — and swallows connectivity failures rather than crashing
  /// whatever settings row triggered it: a Payouts row that can't reach the
  /// backend right now should just read "Not set" a beat longer, not throw
  /// an uncaught error into the widget tree.
  Future<void> load() async {
    final session = ref.read(authControllerProvider);
    if (session == null) return;

    try {
      final banks = await fetchBanks();
      final json = await _repository.fetchExisting(
        userId: session.user.id,
        token: session.accessToken,
      );
      if (json == null) {
        state = null;
        return;
      }
      final bankCode = json['bankCode'] as String;
      final bankName = banks
          .firstWhere((b) => b.code == bankCode, orElse: () => Bank(name: bankCode, code: bankCode))
          .name;
      state = PayoutAccount(
        bankCode: bankCode,
        bankName: bankName,
        accountNumber: json['accountNumber'] as String,
        accountName: json['accountName'] as String,
      );
    } catch (_) {
      // Leave state as-is — a stale-but-known account beats replacing it
      // with nothing just because this particular refresh failed.
    }
  }

  Future<PayoutAccount> verifyAndSave({
    required Bank bank,
    required String accountNumber,
  }) async {
    final session = ref.read(authControllerProvider);
    if (session == null) {
      throw StateError('verifyAndSave called with no active session');
    }
    final account = await _repository.resolveAndSave(
      userId: session.user.id,
      bank: bank,
      accountNumber: accountNumber,
      token: session.accessToken,
    );
    state = account;
    return account;
  }
}

final payoutControllerProvider =
    NotifierProvider<PayoutController, PayoutAccount?>(PayoutController.new);

/// Cached for the life of the provider container — Paystack's bank list is
/// effectively static, so the picker doesn't need to refetch it every time
/// it's opened.
final banksProvider = FutureProvider<List<Bank>>(
  (ref) => ref.read(payoutControllerProvider.notifier).fetchBanks(),
);
