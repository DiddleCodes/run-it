/// A row in the Wallet screen's "Recent transactions" list — wired to the
/// real `GET /wallet/:userId/transactions` (Task 8b/32), not local/demo
/// data.
enum WalletTransactionKind { debit, credit }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    required this.occurredAt,
    required this.status,
  });

  final String id;
  final String title;
  final String subtitle;
  final int amount;
  final WalletTransactionKind kind;
  final DateTime occurredAt;

  /// Real backend WalletTransactionStatus: 'pending' | 'success' | 'failed'.
  /// A withdrawal (Task 32) is the one row type a caller actually needs to
  /// poll this for — every other transaction type is only ever created
  /// already-settled.
  final String status;
}
