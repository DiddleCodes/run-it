import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/payout_models.dart';

/// Real backend calls against the Task 8b payments service — unlike most
/// other repositories in this app ([AuthRepository], `WalletBalanceController`),
/// this one is not client-mocked: a "verify this bank account" flow only
/// means something if it actually round-trips through Paystack's
/// resolve-account endpoint.
class PayoutRepository {
  const PayoutRepository({this.client = const ApiClient()});

  final ApiClient client;

  Future<List<Bank>> fetchBanks({required String token}) async {
    final data = await client.get('/payout-accounts/banks', token: token) as List<dynamic>;
    return data
        .cast<Map<String, dynamic>>()
        .map((json) => Bank(name: json['name'] as String, code: json['code'] as String))
        .toList();
  }

  /// Raw JSON for the caller to enrich with a bank name it already knows
  /// (see [PayoutController.load]) — this repository has no bank-list
  /// context of its own to resolve `bankCode` back to a label.
  Future<Map<String, dynamic>?> fetchExisting({
    required String userId,
    required String token,
  }) async {
    try {
      return await client.get('/payout-accounts/$userId', token: token)
          as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Resolves [accountNumber]/[bank] via Paystack and, only on success,
  /// persists it server-side — the backend couples verify and save into
  /// one atomic call (Task 8b), so there's no separate save step once this
  /// returns; a caller's own "confirm" step afterward is a client-side
  /// acknowledgement of what's already been saved, not a second request.
  Future<PayoutAccount> resolveAndSave({
    required String userId,
    required Bank bank,
    required String accountNumber,
    required String token,
  }) async {
    final json = await client.post(
      '/payout-accounts',
      token: token,
      body: {
        'userId': userId,
        'bankCode': bank.code,
        'accountNumber': accountNumber,
      },
    ) as Map<String, dynamic>;
    return PayoutAccount(
      bankCode: bank.code,
      bankName: bank.name,
      accountNumber: json['accountNumber'] as String,
      accountName: json['accountName'] as String,
    );
  }
}
