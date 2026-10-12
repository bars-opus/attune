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

/// "1,234.5" in USD -> 123450. Null for anything that is not a plain,
/// non-negative amount with at most the currency's decimal places.
int? parsePlanningMoney(String input, String currency) {
  final digits = planningCurrencyDigits(currency);
  final s = input.trim().replaceAll(',', '');
  final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(s);
  if (m == null) return null;
  final fraction = m.group(2) ?? '';
  if (fraction.length > digits) return null;
  final whole = m.group(1)!;
  if (whole.length > 13) return null;
  final minor = int.parse(whole + fraction.padRight(digits, '0'));
  return minor > planningMaxMinor ? null : minor;
}
