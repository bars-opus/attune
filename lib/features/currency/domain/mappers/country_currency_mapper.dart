// lib/features/shop/creation/domain/mappers/country_currency_mapper.dart

import '../entities/currency.dart';

/// Maps country codes to their primary currencies
class CountryCurrencyMapper {
  // ISO 3166-1 alpha-2 country codes to primary currency
  static const Map<String, String> _primaryCurrency = {
    // North America
    'US': 'USD',
    'CA': 'CAD',
    'MX': 'MXN',

    // Europe
    'GB': 'GBP',
    'DE': 'EUR',
    'FR': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    'NL': 'EUR',
    'BE': 'EUR',
    'AT': 'EUR',
    'CH': 'CHF',
    'SE': 'SEK',
    'NO': 'NOK',
    'DK': 'DKK',
    'PL': 'PLN',
    'CZ': 'CZK',
    'HU': 'HUF',

    // Asia
    'JP': 'JPY',
    'CN': 'CNY',
    'IN': 'INR',
    'KR': 'KRW',
    'SG': 'SGD',
    'HK': 'HKD',
    'TW': 'TWD',
    'TH': 'THB',
    'VN': 'VND',
    'MY': 'MYR',
    'ID': 'IDR',
    'PH': 'PHP',

    // Oceania
    'AU': 'AUD',
    'NZ': 'NZD',

    // South America
    'BR': 'BRL',
    'AR': 'ARS',
    'CL': 'CLP',
    'CO': 'COP',
    'PE': 'PEN',

    // Middle East
    'AE': 'AED',
    'SA': 'SAR',
    'IL': 'ILS',
    'TR': 'TRY',

    // Middle East (extended)
    'QA': 'QAR',
    'KW': 'KWD',

    // Asia (extended)
    'PK': 'PKR',
    'BD': 'BDT',

    // Europe (extended)
    'RO': 'RON',

    // Africa
    'ZA': 'ZAR',
    'NG': 'NGN',
    'GH': 'GHS',
    'KE': 'KES',
    'EG': 'EGP',
    'ET': 'ETB',
    'TZ': 'TZS',
    'UG': 'UGX',
    'SN': 'XOF',
    'CI': 'XOF',
    'MA': 'MAD',
  };

  /// Countries that commonly use multiple currencies
  static const Map<String, List<String>> _multiCurrencyCountries = {
    'PA': ['USD', 'PAB'], // Panama: USD and Panamanian Balboa
    'EC': ['USD'], // Ecuador uses USD
    'ZW': ['USD', 'ZWL'], // Zimbabwe
    'LB': ['LBP', 'USD'], // Lebanon
    'KH': ['KHR', 'USD'], // Cambodia
    'CU': ['CUP', 'CUC', 'USD'], // Cuba
  };

  /// Get primary currency code for a country (returns String)
  static String? getPrimaryCurrencyCode(String? countryCode) {
    if (countryCode == null) return null;
    return _primaryCurrency[countryCode.toUpperCase()];
  }

  /// Get currency object for a country
  static Currency? getPrimaryCurrency(String? countryCode) {
    final code = getPrimaryCurrencyCode(countryCode);
    return Currencies.fromCode(code);
  }

  /// Get all possible currency codes for a country
  static List<String> getCurrencyCodesForCountry(String? countryCode) {
    if (countryCode == null) return [];
    final code = countryCode.toUpperCase();

    // Return multi-currency list if exists, otherwise primary as single-item list
    return _multiCurrencyCountries[code] ??
        [getPrimaryCurrencyCode(code)].whereType<String>().toList();
  }

  /// Get all possible currency objects for a country
  static List<Currency> getCurrenciesForCountry(String? countryCode) {
    final codes = getCurrencyCodesForCountry(countryCode);
    return codes
        .map((code) => Currencies.fromCode(code))
        .whereType<Currency>()
        .toList();
  }

  /// Check if a country has multiple currency options
  static bool hasMultipleCurrencies(String? countryCode) {
    if (countryCode == null) return false;
    return _multiCurrencyCountries.containsKey(countryCode.toUpperCase());
  }

  /// Get a user-friendly message for multi-currency countries
  static String? getMultiCurrencyMessage(String? countryCode) {
    if (!hasMultipleCurrencies(countryCode)) return null;

    final currencies = getCurrenciesForCountry(countryCode);
    if (currencies.isEmpty) return null;

    final names = currencies.map((c) => '${c.code} (${c.symbol})').join(', ');
    return 'This country uses $names. Please select the appropriate one.';
  }
}
