import 'package:intl/intl.dart';

/// Money is integer minor units plus an ISO 4217 code (checklist 2.19).
/// Typed amounts are parsed as strings, never through a double.

/// The server's cap on one amount (planning_v2_rich_item_fields).
const planningMaxMinor = 1000000000000;

int planningCurrencyDigits(String currency) =>
    NumberFormat.simpleCurrency(name: currency).decimalDigits ?? 2;

String formatPlanningMoney(int minor, String currency, {String? locale}) {
  final f = NumberFormat.simpleCurrency(name: currency, locale: locale);
  final digits = f.decimalDigits ?? 2;
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }
  return f.format(minor / divisor);
}

/// Reads a typed amount into minor units without floating point. Both
/// "12.50" and "12,50" are decimals (a comma is what the keypad types in
/// much of the world); a separator followed by exactly three digits is
/// grouping ("1,234", "1.234"); with both present the last one is the
/// decimal ("1.234,50", "1,234.50"). Null for anything else, including
/// more decimals than the currency has.
int? parsePlanningMoney(String input, String currency) {
  final digits = planningCurrencyDigits(currency);
  final s = input.trim().replaceAll(RegExp(r'[\s\u00a0\u202f]'), '');
  if (!RegExp(r'^[0-9][0-9.,]*$').hasMatch(s)) return null;

  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  int? decimalAt;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalAt = lastDot > lastComma ? lastDot : lastComma;
  } else {
    final at = lastDot >= 0 ? lastDot : lastComma;
    final sep = at >= 0 ? s[at] : null;
    final tail = at >= 0 ? s.length - at - 1 : 0;
    if (sep != null && sep.allMatches(s).length == 1 && tail >= 1 && tail <= digits) decimalAt = at;
  }

  final wholePart = decimalAt == null ? s : s.substring(0, decimalAt);
  final fraction = decimalAt == null ? '' : s.substring(decimalAt + 1);
  if (fraction.contains(RegExp(r'[.,]')) || fraction.length > digits) return null;

  // Grouping: 1-3 leading digits, then groups of exactly three.
  final groups = wholePart.split(RegExp(r'[.,]'));
  if (groups.length > 1) {
    final grouping = wholePart.replaceAll(RegExp(r'[0-9]'), '');
    if (grouping.split('').toSet().length > 1) return null; // "1.234,567,8"
    if (groups.first.isEmpty || groups.first.length > 3) return null;
    if (groups.skip(1).any((g) => g.length != 3)) return null;
  }
  final whole = groups.join();
  if (whole.isEmpty || whole.length > 13) return null;
  final minor = int.parse(whole + fraction.padRight(digits, '0'));
  return minor > planningMaxMinor ? null : minor;
}

/// A short amount for tight spaces like chart wedges: "GHS200", "GHS2.5K".
String formatPlanningMoneyCompact(int minor, String currency) {
  var divisor = 1;
  for (var i = planningCurrencyDigits(currency); i > 0; i--) {
    divisor *= 10;
  }
  return NumberFormat.compactSimpleCurrency(name: currency).format(minor / divisor);
}
