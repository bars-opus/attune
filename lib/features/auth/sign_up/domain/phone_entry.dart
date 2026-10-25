import 'package:phone_numbers_parser/metadata.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// A3's number rules (Spec 1 §3.3): parsed for the chosen country with
/// phone_numbers_parser; a leading national 0 is accepted and dropped; the
/// result is E.164.
enum PhoneEntryError { tooShort, tooLong, wrongCountry }

({String? e164, PhoneEntryError? error}) parsePhoneEntry(
  String input,
  String isoCode,
) {
  final iso = _iso(isoCode);
  final digits = input.replaceAll(RegExp(r'\D'), '');
  if (iso == null) return (e164: null, error: PhoneEntryError.wrongCountry);
  if (digits.length < 4) return (e164: null, error: PhoneEntryError.tooShort);

  final PhoneNumber parsed;
  try {
    parsed = PhoneNumber.parse(
      input,
      callerCountry: iso,
      destinationCountry: iso,
    );
  } on PhoneNumberException {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }
  final expectedCode = metadataByIsoCode[iso]!.countryCode;
  if (parsed.countryCode != expectedCode) {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }

  final lengths = metadataLenghtsByIsoCode[parsed.isoCode]!;
  final allowed = {...lengths.general, ...lengths.mobile, ...lengths.fixedLine};
  if (allowed.isNotEmpty) {
    final shortest = allowed.reduce((a, b) => a < b ? a : b);
    final longest = allowed.reduce((a, b) => a > b ? a : b);
    if (parsed.nsn.length < shortest) {
      return (e164: null, error: PhoneEntryError.tooShort);
    }
    if (parsed.nsn.length > longest) {
      return (e164: null, error: PhoneEntryError.tooLong);
    }
  }
  if (!parsed.isValid()) {
    return (e164: null, error: PhoneEntryError.wrongCountry);
  }
  return (e164: parsed.international, error: null);
}

/// "+233 24 412 3456", for A4's subtitle and the WhatsApp sheet.
String formatPhoneForDisplay(String e164) {
  try {
    final parsed = PhoneNumber.parse(e164);
    return '+${parsed.countryCode} ${parsed.formatNsn()}';
  } on PhoneNumberException {
    return e164;
  }
}

/// The ISO country of an E.164 number, or null.
String? countryOfPhone(String e164) {
  try {
    return PhoneNumber.parse(e164).isoCode.name;
  } on PhoneNumberException {
    return null;
  }
}

IsoCode? _iso(String code) {
  try {
    return IsoCode.values.byName(code.toUpperCase());
  } on ArgumentError {
    return null;
  }
}
