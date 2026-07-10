import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final selectedPhoneCountryProvider = StateProvider.autoDispose<PhoneCountry>(
  (ref) => PhoneCountries.defaultCountry,
);
