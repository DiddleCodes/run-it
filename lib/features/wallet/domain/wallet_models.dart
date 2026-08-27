/// A row in the Wallet screen's "Recent transactions" list. Local/demo
/// data only — there's no ledger backend yet, same spirit as the runner
/// side's `EarningsRecord`/`SystemNotice`.
enum WalletTransactionKind { debit, credit }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    required this.occurredAt,
  });

  final String id;
  final String title;
  final String subtitle;
  final int amount;
  final WalletTransactionKind kind;
  final DateTime occurredAt;
}
