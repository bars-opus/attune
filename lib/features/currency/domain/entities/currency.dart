// lib/features/shop/creation/domain/entities/currency.dart

import 'package:equatable/equatable.dart';

// lib/features/shop/creation/domain/entities/currency.dart

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Represents a currency with ISO code, symbol, display name, and flag emoji
class Currency extends Equatable {
  final String code; // ISO 4217 code: USD, EUR, GBP
  final String symbol; // $, €, £
  final String name; // US Dollar, Euro, British Pound
  final String flag; // 🇺🇸, 🇪🇺, 🇬🇧
  final int decimalDigits; // 2 for most currencies, 0 for JPY

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.flag,
    this.decimalDigits = 2,
  });

  /// Display format: "🇺🇸 USD ($) - US Dollar"
  String get displayName => '$flag $code ($symbol) - $name';

  /// Short display: "🇺🇸 USD ($)"
  String get shortDisplay => '$flag $code ($symbol)';

  /// Format a price with this currency
  String formatPrice(double amount) {
    if (decimalDigits == 0) {
      return '$symbol${amount.toStringAsFixed(0)}';
    }
    return '$symbol${amount.toStringAsFixed(decimalDigits)}';
  }

  /// Format price with currency code: "$45.00 USD"
  String formatPriceWithCode(double amount) {
    return '${formatPrice(amount)} $code';
  }

  @override
  List<Object?> get props => [code, symbol, name, flag, decimalDigits];
}

/// Predefined list of major currencies with flags
class Currencies {
  static const List<Currency> all = [
    Currency(code: 'USD', symbol: '\$', name: 'US Dollar', flag: '🇺🇸'),
    Currency(code: 'EUR', symbol: '€', name: 'Euro', flag: '🇪🇺'),
    Currency(code: 'GBP', symbol: '£', name: 'British Pound', flag: '🇬🇧'),
    Currency(
      code: 'JPY',
      symbol: '¥',
      name: 'Japanese Yen',
      flag: '🇯🇵',
      decimalDigits: 0,
    ),
    Currency(code: 'CAD', symbol: 'C\$', name: 'Canadian Dollar', flag: '🇨🇦'),
    Currency(
      code: 'AUD',
      symbol: 'A\$',
      name: 'Australian Dollar',
      flag: '🇦🇺',
    ),
    Currency(code: 'CHF', symbol: 'Fr', name: 'Swiss Franc', flag: '🇨🇭'),
    Currency(code: 'CNY', symbol: '¥', name: 'Chinese Yuan', flag: '🇨🇳'),
    Currency(code: 'INR', symbol: '₹', name: 'Indian Rupee', flag: '🇮🇳'),
    Currency(code: 'BRL', symbol: 'R\$', name: 'Brazilian Real', flag: '🇧🇷'),
    Currency(code: 'MXN', symbol: '\$', name: 'Mexican Peso', flag: '🇲🇽'),
    Currency(
      code: 'SGD',
      symbol: 'S\$',
      name: 'Singapore Dollar',
      flag: '🇸🇬',
    ),
    Currency(
      code: 'NZD',
      symbol: 'NZ\$',
      name: 'New Zealand Dollar',
      flag: '🇳🇿',
    ),
    Currency(
      code: 'HKD',
      symbol: 'HK\$',
      name: 'Hong Kong Dollar',
      flag: '🇭🇰',
    ),
    Currency(
      code: 'KRW',
      symbol: '₩',
      name: 'South Korean Won',
      flag: '🇰🇷',
      decimalDigits: 0,
    ),
    Currency(code: 'SEK', symbol: 'kr', name: 'Swedish Krona', flag: '🇸🇪'),
    Currency(code: 'NOK', symbol: 'kr', name: 'Norwegian Krone', flag: '🇳🇴'),
    Currency(code: 'DKK', symbol: 'kr', name: 'Danish Krone', flag: '🇩🇰'),
    Currency(code: 'PLN', symbol: 'zł', name: 'Polish Złoty', flag: '🇵🇱'),
    Currency(code: 'TRY', symbol: '₺', name: 'Turkish Lira', flag: '🇹🇷'),
    Currency(code: 'AED', symbol: 'د.إ', name: 'UAE Dirham', flag: '🇦🇪'),
    Currency(
      code: 'ZAR',
      symbol: 'R',
      name: 'South African Rand',
      flag: '🇿🇦',
    ),
    Currency(code: 'ILS', symbol: '₪', name: 'Israeli Shekel', flag: '🇮🇱'),
    Currency(code: 'THB', symbol: '฿', name: 'Thai Baht', flag: '🇹🇭'),
    // Africa
    Currency(code: 'GHS', symbol: '₵', name: 'Ghanaian Cedi', flag: '🇬🇭'),
    Currency(code: 'NGN', symbol: '₦', name: 'Nigerian Naira', flag: '🇳🇬'),
    Currency(code: 'KES', symbol: 'KSh', name: 'Kenyan Shilling', flag: '🇰🇪'),
    Currency(code: 'EGP', symbol: 'E£', name: 'Egyptian Pound', flag: '🇪🇬'),
    Currency(code: 'ETB', symbol: 'Br', name: 'Ethiopian Birr', flag: '🇪🇹'),
    Currency(code: 'TZS', symbol: 'TSh', name: 'Tanzanian Shilling', flag: '🇹🇿', decimalDigits: 0),
    Currency(code: 'UGX', symbol: 'USh', name: 'Ugandan Shilling', flag: '🇺🇬', decimalDigits: 0),
    Currency(code: 'XOF', symbol: 'CFA', name: 'West African CFA Franc', flag: '🌍', decimalDigits: 0),
    Currency(code: 'MAD', symbol: 'MAD', name: 'Moroccan Dirham', flag: '🇲🇦'),
    // Middle East
    Currency(code: 'SAR', symbol: '﷼', name: 'Saudi Riyal', flag: '🇸🇦'),
    Currency(code: 'QAR', symbol: '﷼', name: 'Qatari Riyal', flag: '🇶🇦'),
    Currency(code: 'KWD', symbol: 'KD', name: 'Kuwaiti Dinar', flag: '🇰🇼', decimalDigits: 3),
    // Asia
    Currency(code: 'MYR', symbol: 'RM', name: 'Malaysian Ringgit', flag: '🇲🇾'),
    Currency(code: 'PHP', symbol: '₱', name: 'Philippine Peso', flag: '🇵🇭'),
    Currency(code: 'IDR', symbol: 'Rp', name: 'Indonesian Rupiah', flag: '🇮🇩', decimalDigits: 0),
    Currency(code: 'VND', symbol: '₫', name: 'Vietnamese Dong', flag: '🇻🇳', decimalDigits: 0),
    Currency(code: 'TWD', symbol: 'NT\$', name: 'Taiwan Dollar', flag: '🇹🇼'),
    Currency(code: 'PKR', symbol: '₨', name: 'Pakistani Rupee', flag: '🇵🇰'),
    Currency(code: 'BDT', symbol: '৳', name: 'Bangladeshi Taka', flag: '🇧🇩'),
    // Europe
    Currency(code: 'CZK', symbol: 'Kč', name: 'Czech Koruna', flag: '🇨🇿'),
    Currency(code: 'HUF', symbol: 'Ft', name: 'Hungarian Forint', flag: '🇭🇺', decimalDigits: 0),
    Currency(code: 'RON', symbol: 'lei', name: 'Romanian Leu', flag: '🇷🇴'),
    // Latin America
    Currency(code: 'ARS', symbol: '\$', name: 'Argentine Peso', flag: '🇦🇷'),
    Currency(code: 'CLP', symbol: '\$', name: 'Chilean Peso', flag: '🇨🇱', decimalDigits: 0),
    Currency(code: 'COP', symbol: '\$', name: 'Colombian Peso', flag: '🇨🇴', decimalDigits: 0),
    Currency(code: 'PEN', symbol: 'S/', name: 'Peruvian Sol', flag: '🇵🇪'),
  ];

  /// Get currency by ISO code
  static Currency? fromCode(String? code) {
    if (code == null) return null;
    try {
      return all.firstWhere((c) => c.code == code);
    } catch (e) {
      return null;
    }
  }

  /// Get default currency (USD)
  static Currency get defaultCurrency => all.firstWhere((c) => c.code == 'USD');
}
