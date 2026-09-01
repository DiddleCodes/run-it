/// One entry from Paystack's List Banks endpoint (proxied by the backend
/// at `GET /payout-accounts/banks`) — just enough to populate the picker
/// and send `code` back on save.
class Bank {
  const Bank({required this.name, required this.code});

  final String name;
  final String code;
}

/// A restaurant's or runner's saved payout account. Mirrors the backend's
/// `payout_accounts` row (Task 8b) — [accountName] always comes back from
/// Paystack's resolve-account response, never typed by the user, so it
/// can't be spoofed. [bankName] isn't part of that row (the backend only
/// stores `bankCode`) — it's filled in locally from whichever [Bank] the
/// picker returned, so callers never have to re-resolve a code to a label.
class PayoutAccount {
  const PayoutAccount({
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
  });

  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountName;

  Bank get bank => Bank(name: bankName, code: bankCode);

  /// e.g. "•••• 4417" — every digit but the last four, matching how a
  /// saved card/account is conventionally shown back to its owner.
  String get maskedAccountNumber => accountNumber.length <= 4
      ? accountNumber
      : '•••• ${accountNumber.substring(accountNumber.length - 4)}';
}
