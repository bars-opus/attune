// lib/features/shop/creation/utils/price_formatter.dart



import 'package:attune/features/currency/domain/entities/currency.dart';

class PriceFormatter {
  /// Format price with currency symbol only
  static String format(double price, Currency? currency) {
    if (currency == null) {
      return '\$${price.toStringAsFixed(2)}'; // Default to USD
    }
    return currency.formatPrice(price);
  }

  /// Format price with currency code (e.g., "$45.00 USD")
  static String formatWithCode(double price, Currency? currency) {
    if (currency == null) {
      return '\$${price.toStringAsFixed(2)} USD';
    }
    return currency.formatPriceWithCode(price);
  }

  /// Format price for display in lists (shorter)
  static String formatShort(double price, Currency? currency) {
    if (currency == null) {
      return '\$${price.toStringAsFixed(0)}';
    }
    if (currency.decimalDigits == 0) {
      return '${currency.symbol}${price.toStringAsFixed(0)}';
    }
    return '${currency.symbol}${price.toStringAsFixed(0)}';
  }

  /// Get currency symbol
  static String getSymbol(Currency? currency) {
    return currency?.symbol ?? '\$';
  }

  /// Parse string to double with validation
  static double? parsePrice(String value) {
    try {
      return double.parse(value);
    } catch (e) {
      return null;
    }
  }
}
