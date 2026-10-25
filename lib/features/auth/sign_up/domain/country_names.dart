import 'package:attune/features/auth/log_in/domain/phone_country.dart';

/// Names a list of ISO 3166-1 alpha-2 codes for a sentence: "Ghana",
/// "Ghana and the UK", "Ghana, Kenya and the UK". [nameOf] names one code;
/// [pair] joins two names in the reader's language.
String formatCountryList(
  List<String> isoCodes, {
  required String Function(String iso) nameOf,
  required String Function(String first, String second) pair,
}) {
  final names = [for (final iso in isoCodes) nameOf(iso)];
  if (names.isEmpty) return '';
  if (names.length == 1) return names.single;
  return pair(names.sublist(0, names.length - 1).join(', '), names.last);
}

/// A country's English name from the phone country list, or [iso] itself
/// when the code is unknown. [special] covers the names a sentence says
/// differently ("the UK", "the US").
String countryNameFor(String iso, {Map<String, String> special = const {}}) {
  final upper = iso.toUpperCase();
  final override = special[upper];
  if (override != null) return override;
  for (final country in PhoneCountries.all) {
    if (country.isoCode == upper) return country.name;
  }
  return upper;
}
