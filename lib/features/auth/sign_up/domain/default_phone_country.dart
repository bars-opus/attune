import 'package:attune/features/auth/log_in/domain/phone_country.dart';

/// A3's default country (Spec 1 §3.3): the Android SIM's country, else the
/// device region, else none (the picker opens). Never a hard-coded Ghana.
PhoneCountry? defaultPhoneCountry({
  String? simIso,
  String? regionIso,
  List<PhoneCountry>? countries,
}) {
  final all = countries ?? PhoneCountries.all;
  for (final candidate in [simIso, regionIso]) {
    if (candidate == null || candidate.trim().isEmpty) continue;
    final iso = candidate.trim().toUpperCase();
    for (final country in all) {
      if (country.isoCode == iso) return country;
    }
  }
  return null;
}
