import 'package:intl/intl.dart';

final _wholeNaira = NumberFormat('#,##0', 'en_US');

/// The one way money is shown in the app: ₦1,444.50 — thousands separated,
/// always two decimals. Integer maths on kobo, so no floating-point drift.
String formatKobo(int kobo) {
  final sign = kobo < 0 ? '-' : '';
  final abs = kobo.abs();
  final kobos = (abs % 100).toString().padLeft(2, '0');
  return '$sign₦${_wholeNaira.format(abs ~/ 100)}.$kobos';
}

/// [formatKobo] for an amount held in naira (menu prices, the checkout
/// breakdown, the wallet balance) — fractional naira keep their kobo.
String naira(num amount) => formatKobo((amount * 100).round());
