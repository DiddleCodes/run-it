import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/wallet_models.dart';

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => const WalletRepository(),
);

/// Real backend calls against the Task 8b payments service. Every amount
/// here crosses the naira/kobo boundary exactly once — the backend deals
/// exclusively in integer kobo (never a float), while the rest of this app
/// (like every other screen) deals in whole naira, so this repository
/// converts at the edge and every caller above it stays kobo-free.
class WalletRepository {
  const WalletRepository({this.client = const ApiClient()});

  final ApiClient client;

  /// Starts a Paystack charge for [amountNaira] and returns the checkout
  /// details the client needs to launch Paystack's hosted checkout —
  /// `reference` is what a later balance-poll or transaction lookup
  /// correlates back to this specific attempt.
  Future<WalletFundingIntent> initializeFunding({
    required String userId,
    required String email,
    required int amountNaira,
    required String token,
  }) async {
    final json =
        await client.post(
              '/wallet/fund/initialize',
              token: token,
              body: {
                'userId': userId,
                'email': email,
                'amountKobo': amountNaira * 100,
              },
            )
            as Map<String, dynamic>;
    return WalletFundingIntent(
      reference: json['reference'] as String,
      authorizationUrl: json['authorizationUrl'] as String,
      accessCode: json['accessCode'] as String,
    );
  }

  Future<int> getBalance({required String userId, required String token}) async {
    final json = await client.get('/wallet/$userId/balance', token: token) as Map<String, dynamic>;
    return (json['balanceKobo'] as int) ~/ 100;
  }

  Future<List<WalletTransaction>> getTransactions({
    required String userId,
    required String token,
  }) async {
    final data = await client.get('/wallet/$userId/transactions', token: token) as List<dynamic>;
    return data.cast<Map<String, dynamic>>().map(_toTransaction).toList();
  }

  WalletTransaction _toTransaction(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>?;
    final purpose = metadata?['purpose'] as String?;
    final (title, subtitle) = switch (purpose) {
      'wallet_topup' => ('Wallet top-up', 'Paystack'),
      'escrow_hold' => ('Order payment', 'Food order'),
      'escrow_refund' => ('Order refund', 'Cancelled order'),
      _ => ('Wallet transaction', json['status'] as String? ?? ''),
    };
    return WalletTransaction(
      id: json['id'] as String,
      title: title,
      subtitle: subtitle,
      amount: (json['amount'] as int) ~/ 100,
      kind: json['type'] == 'credit' ? WalletTransactionKind.credit : WalletTransactionKind.debit,
      occurredAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// What the backend hands back from `POST /wallet/fund/initialize` — enough
/// for the client to launch Paystack's hosted checkout against an
/// already-server-initialized transaction (the secret key never leaves the
/// backend).
class WalletFundingIntent {
  const WalletFundingIntent({
    required this.reference,
    required this.authorizationUrl,
    required this.accessCode,
  });

  final String reference;
  final String authorizationUrl;
  final String accessCode;
}
