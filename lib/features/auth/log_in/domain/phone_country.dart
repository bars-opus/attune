import 'package:countries_utils/countries_utils.dart' as country_data;
import 'package:phone_numbers_parser/metadata.dart' as phone_metadata;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

class PhoneCountry {
  const PhoneCountry({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.flag,
    required this.example,
  });

  final String isoCode;
  final String name;
  final String dialCode;
  final String flag;
  final String example;

  bool matches(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;

    return name.toLowerCase().contains(normalizedQuery) ||
        isoCode.toLowerCase().contains(normalizedQuery) ||
        dialCode.contains(normalizedQuery.replaceAll('+', '')) ||
        flag.contains(normalizedQuery);
  }
}

class PhoneCountries {
  const PhoneCountries._();

  static final List<PhoneCountry> all = _buildCountries();

  static PhoneCountry get ghana => all.firstWhere(
    (country) => country.isoCode == 'GH',
    orElse: () => all.first,
  );

  static PhoneCountry get defaultCountry => ghana;

  static List<PhoneCountry> _buildCountries() {
    final countries =
        country_data.Countries.all()
            .map(_fromCountry)
            .whereType<PhoneCountry>()
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    return List.unmodifiable(countries);
  }

  static PhoneCountry? _fromCountry(country_data.Country country) {
    final isoCode = country.alpha2Code;
    final name = country.name;
    if (isoCode == null || name == null) return null;

    final iso = _tryIsoCode(isoCode);
    if (iso == null) return null;

    final metadata = phone_metadata.metadataByIsoCode[iso];
    if (metadata == null) return null;

    final example = _exampleFor(iso);
    return PhoneCountry(
      isoCode: iso.name,
      name: _displayName(name),
      dialCode: '+${metadata.countryCode}',
      flag: country.flagIcon ?? iso.name,
      example: example,
    );
  }

  static IsoCode? _tryIsoCode(String code) {
    try {
      return IsoCode.values.byName(code.toUpperCase());
    } on ArgumentError {
      return null;
    }
  }

  static String _exampleFor(IsoCode iso) {
    final examples = phone_metadata.metadataExamplesByIsoCode[iso];
    if (examples == null) return '';

    final nsn = [
      examples.mobile,
      examples.fixedLine,
      examples.voip,
      examples.tollFree,
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (nsn.isEmpty) return '';

    return PhoneNumber(isoCode: iso, nsn: nsn).formatNsn();
  }

  static String _displayName(String name) {
    return switch (name) {
      'United Kingdom of Great Britain and Northern Ireland' =>
        'United Kingdom',
      'United States of America' => 'United States',
      _ => name,
    };
  }
}
