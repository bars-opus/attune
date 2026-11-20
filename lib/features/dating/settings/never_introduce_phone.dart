// Spec 2 W5c Task 9 fix round 1 (C-1): the number a person types or pastes
// into "Never introduce me", as the E.164 number it really is. A number
// written in full (`+233 24 …`, `00233 24 …`, as contacts keep it) keeps
// its own country code whatever the picker says; anything else is read as
// a number of the picked country (its trunk 0 dropped). A number that
// isn't a real number for its country is refused here, before anything is
// sent: a format check, so it says nothing about who uses it. The picker
// starts on the country of the account's own phone.
//
// W5 final fix (M-6, T9 N-2 Ruling): the add takes a number of a possible
// length for its country, not only one in the library's known ranges: an
// exposure-reducing add of a range newer than the bundled metadata harms
// nobody, while refusing it leaves a person unprotected. A number the
// library knows is still read its way first (the country of a `+` number
// is the one it is valid for); anything that isn't digits, or is too
// short or too long for the country, is still refused.
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_numbers_parser/metadata.dart' show metadataByIsoCode;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

final _e164 = RegExp(r'^\+[1-9][0-9]{7,14}$');

/// Digits, with at most a leading `+` (after the spacing is taken out).
final _digitsOnly = RegExp(r'^\+?[0-9]+$');

PhoneNumber? _parse(String text, [IsoCode? country]) {
  try {
    return country == null
        ? PhoneNumber.parse(text)
        : PhoneNumber.parse(text, destinationCountry: country);
  } on PhoneNumberException {
    return null;
  }
}

/// [text] as an E.164 number, read for [country] unless it carries its
/// own code; null when it isn't a number of a possible length.
String? datingNeverE164(String text, PhoneCountry country) {
  final compact = text.trim().replaceAll(RegExp(r'[\s().\-]'), '');
  if (compact.isEmpty) return null;
  final full = compact.startsWith('00') ? '+${compact.substring(2)}' : compact;
  if (!_digitsOnly.hasMatch(full)) return null;
  final readings = <PhoneNumber?>[];
  if (full.startsWith('+')) {
    readings.add(_parse(full));
  } else {
    final iso = IsoCode.values.asNameMap()[country.isoCode];
    if (iso == null) return null;
    readings.add(_parse(full, iso));
    // A range the library doesn't know keeps its trunk prefix when parsed
    // (GH 025…, 060…), so it is read again without it.
    final trunk = metadataByIsoCode[iso]?.nationalPrefix ?? '';
    if (trunk.isNotEmpty &&
        full.startsWith(trunk) &&
        full.length > trunk.length) {
      readings.add(_parse(full.substring(trunk.length), iso));
    }
  }
  final numbers = readings.whereType<PhoneNumber>().toList();
  // A known number first; else a possible length, without the trunk
  // prefix when there is one (the last reading).
  final number =
      numbers.where((n) => n.isValid()).firstOrNull ??
      numbers.where((n) => n.isValidLength()).lastOrNull;
  final value = number?.international;
  if (value == null || !_e164.hasMatch(value)) return null;
  return value;
}

/// The country of [phone] (the account's phone, with or without its `+`),
/// else the app's default country.
PhoneCountry datingCountryForPhone(String? phone) {
  final digits = phone?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.isEmpty) return PhoneCountries.defaultCountry;
  try {
    final iso = PhoneNumber.parse('+$digits').isoCode.name;
    return PhoneCountries.all.firstWhere(
      (c) => c.isoCode == iso,
      orElse: () => PhoneCountries.defaultCountry,
    );
  } on PhoneNumberException {
    return PhoneCountries.defaultCountry;
  }
}

/// The picker's first country: the signed-in account's phone's country.
final datingNeverCountryProvider = Provider<PhoneCountry>(
  (ref) => datingCountryForPhone(
    ref.watch(currentUserProvider.select((u) => u?.phone)),
  ),
);
