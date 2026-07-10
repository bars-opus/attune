import 'package:attune/core/utils/validation/validation_result.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes local Ghana number to E.164', () {
    expect(
      ValidationUtils.normalizePhoneNumber(
        dialCode: PhoneCountries.ghana.dialCode,
        nationalNumber: '024 000 0000',
        isoCode: PhoneCountries.ghana.isoCode,
      ),
      '+233240000000',
    );
  });

  test('accepts already-prefixed Ghana number', () {
    expect(
      ValidationUtils.normalizePhoneNumber(
        dialCode: PhoneCountries.ghana.dialCode,
        nationalNumber: '233240000000',
        isoCode: PhoneCountries.ghana.isoCode,
      ),
      '+233240000000',
    );
  });

  test('validates country-specific national length', () {
    final validResult = ValidationUtils.validatePhoneNumberForCountry(
      '024 000 0000',
      isoCode: PhoneCountries.ghana.isoCode,
      dialCode: PhoneCountries.ghana.dialCode,
      countryName: PhoneCountries.ghana.name,
    );

    expect(validResult.isValid, isTrue);
    expect(validResult.correctedValue, '+233240000000');

    final invalidResult = ValidationUtils.validatePhoneNumberForCountry(
      '240',
      isoCode: PhoneCountries.ghana.isoCode,
      dialCode: PhoneCountries.ghana.dialCode,
      countryName: PhoneCountries.ghana.name,
    );

    expect(invalidResult.isValid, isFalse);
  });

  test('accepts NANP numbers with +1 country code', () {
    final us = PhoneCountries.all.firstWhere((country) => country.isoCode == 'US');

    final result = ValidationUtils.validatePhoneNumberForCountry(
      '1610 342 7892',
      isoCode: us.isoCode,
      dialCode: us.dialCode,
      countryName: us.name,
    );

    expect(result.isValid, isTrue);
    expect(result.correctedValue, '+16103427892');
  });

  test('loads a global country picker list', () {
    expect(PhoneCountries.all.length, greaterThan(190));
    expect(
      PhoneCountries.all.any((country) => country.isoCode == 'JP'),
      isTrue,
    );
  });
}
