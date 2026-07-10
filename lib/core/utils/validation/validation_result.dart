import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:attune/core/utils/validation/validation_utils.dart';
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Validation result with detailed information
class ValidationResult {
  final bool isValid;
  final String? errorMessage;
  final String? fieldName;
  final dynamic correctedValue;
  final Map<String, dynamic> metadata;

  const ValidationResult({
    required this.isValid,
    this.errorMessage,
    this.fieldName,
    this.correctedValue,
    this.metadata = const {},
  });

  const ValidationResult.valid()
    : isValid = true,
      errorMessage = null,
      fieldName = null,
      correctedValue = null,
      metadata = const {};

  ValidationResult.invalid(
    String message, {
    String? field,
    this.correctedValue,
    Map<String, dynamic>? metadata,
  }) : isValid = false,
       errorMessage = message,
       fieldName = field,
       metadata = metadata ?? const {};

  /// Converts to nullable string for Flutter's TextField validator
  String? toErrorString() => isValid ? null : errorMessage;
}

/// Main validation utility class
class ValidationUtils {
  static ValidationConfig _config = ValidationConfig.en();

  /// Set global validation configuration
  static void configure(ValidationConfig config) {
    _config = config;
  }

  // Regex patterns (compiled once for performance)
  // RFC 5321 local-part chars; domain requires at least one dot and a 2+ char TLD.
  // Uses double-quoted raw string to safely include ‘ and ` without terminating.
  static final _emailRegex = RegExp(
    r"^[a-zA-Z0-9.!#$%&’*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$",
    caseSensitive: false,
  );

  static final _passwordUppercaseRegex = RegExp(r'[A-Z]');
  static final _passwordLowercaseRegex = RegExp(r'[a-z]');
  static final _passwordDigitRegex = RegExp(r'\d');
  static final _passwordSpecialCharRegex = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
  static final _multipleSpacesRegex = RegExp(r'\s{2,}');
  static final _creditCardRegex = RegExp(r'^[0-9]{13,19}$');
  static final _postalCodeRegex = RegExp(
    r'^[0-9]{5}(?:-[0-9]{4})?$',
  ); // US format
  static final _ssnRegex = RegExp(r'^\d{3}-\d{2}-\d{4}$');

  // Common disposable email domains
  static const _disposableDomains = {
    'tempmail.com',
    'mailinator.com',
    'guerrillamail.com',
    '10minutemail.com',
    'throwawaymail.com',
    'yopmail.com',
    'trashmail.com',
    'disposablemail.com',
    'fakeinbox.com',
    'temp-mail.org',
    'getairmail.com',
    'maildrop.cc',
    'tempail.com',
    'emailondeck.com',
  };

  // Common weak passwords (top 100)
  static const _weakPasswords = {
    'password',
    '123456',
    '12345678',
    '123456789',
    '12345',
    'qwerty',
    'abc123',
    'password1',
    '123123',
    'admin',
    'welcome',
    'letmein',
    'monkey',
    'login',
    'passw0rd',
    'master',
    'hello',
    'freedom',
    'whatever',
    'qazwsx',
    'trustno1',
    'dragon',
    'baseball',
    'football',
    'iloveyou',
    'sunshine',
    'princess',
    'superman',
    'michael',
    'ninja',
  };

  /* ----------------------------- EMAIL ----------------------------- */

  /// Comprehensive email validation
  static ValidationResult validateEmail(
    String? value, {
    EmailValidationOptions options = const EmailValidationOptions(),
    String? fieldName,
  }) {
    final email = value?.trim();

    if (email == null || email.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Email',
      );
    }

    // Use custom regex if provided, otherwise use default
    final regex = options.customEmailRegex ?? _emailRegex;
    if (!regex.hasMatch(email)) {
      return ValidationResult.invalid(
        _config.messages.invalidEmail,
        field: fieldName,
      );
    }

    // Check for disposable domains
    if (options.checkDisposableDomains) {
      final domain = email.split('@').last.toLowerCase();
      final allDisposableDomains = {
        ..._disposableDomains,
        ...options.additionalDisposableDomains.map((d) => d.toLowerCase()),
      };

      if (allDisposableDomains.contains(domain)) {
        return ValidationResult.invalid(
          _config.messages.disposableEmail,
          field: fieldName,
        );
      }
    }

    // Additional checks
    if (email.length > 254) {
      return ValidationResult.invalid(
        _config.messages.emailTooLong,
        field: fieldName,
      );
    }

    final parts = email.split('@');
    if (parts[0].length > 64) {
      return ValidationResult.invalid(
        _config.messages.emailLocalPartTooLong,
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- PASSWORD ----------------------------- */

  /// Advanced password validation with configurable requirements
  static ValidationResult validatePassword(
    String? value, {
    PasswordRequirements requirements = const PasswordRequirements(),
    String? fieldName,
  }) {
    if (value == null || value.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Password',
      );
    }

    final password = value;

    // Length validation
    if (password.length < requirements.minLength) {
      return ValidationResult.invalid(
        _config.messages.passwordLength.replaceFirst(
          '{length}',
          requirements.minLength.toString(),
        ),
        field: fieldName,
      );
    }

    if (requirements.maxLength != null &&
        password.length > requirements.maxLength!) {
      return ValidationResult.invalid(
        _config.messages.passwordMaxLength.replaceFirst(
          '{max}',
          requirements.maxLength.toString(),
        ),
        field: fieldName,
      );
    }

    // Character type validation
    if (requirements.requireUppercase &&
        !_passwordUppercaseRegex.hasMatch(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordUppercase,
        field: fieldName,
      );
    }

    if (requirements.requireLowercase &&
        !_passwordLowercaseRegex.hasMatch(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordLowercase,
        field: fieldName,
      );
    }

    if (requirements.requireDigits && !_passwordDigitRegex.hasMatch(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordDigit,
        field: fieldName,
      );
    }

    if (requirements.requireSpecialChars &&
        !_passwordSpecialCharRegex.hasMatch(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordSpecialChar,
        field: fieldName,
      );
    }

    // Check against common/weak passwords
    if (requirements.checkCommonPasswords) {
      final lowercasePassword = password.toLowerCase();
      final allDisallowed = {
        ..._weakPasswords,
        ...?(requirements.customDisallowedPasswords?.map(
          (p) => p.toLowerCase(),
        )),
      };

      if (allDisallowed.contains(lowercasePassword)) {
        return ValidationResult.invalid(
          _config.messages.weakPassword,
          field: fieldName,
        );
      }
    }

    // Additional security checks
    if (_hasRepeatingCharacters(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordRepeatingChars,
        field: fieldName,
      );
    }

    if (_isSequential(password)) {
      return ValidationResult.invalid(
        _config.messages.passwordSequential,
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- PHONE ----------------------------- */

  /// Phone number validation with country code support
  static ValidationResult validatePhoneNumber(
    String? value, {
    String? countryCode,
    String? fieldName,
  }) {
    final input = value?.trim();
    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Phone number',
      );
    }

    // Remove all non-digit characters
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');

    // Basic length validation
    if (digitsOnly.length < 7 || digitsOnly.length > 15) {
      return ValidationResult.invalid(
        _config.messages.invalidPhone,
        field: fieldName,
      );
    }

    // Country-specific validation
    if (countryCode != null) {
      switch (countryCode.toUpperCase()) {
        case 'US':
        case 'CA':
          if (digitsOnly.length != 10) {
            return ValidationResult.invalid(
              _config.messages.phoneDigits.replaceFirst('{digits}', '10'),
              field: fieldName,
              correctedValue: _formatPhoneNumber(digitsOnly, countryCode),
            );
          }
          break;
        case 'GB':
          // UK local format is 11 digits; international format (44 prefix) is 12 digits.
          if (digitsOnly.length != 11 &&
              !(digitsOnly.startsWith('44') && digitsOnly.length == 12)) {
            return ValidationResult.invalid(
              _config.messages.phoneUK,
              field: fieldName,
            );
          }
          break;
      }
    }

    return ValidationResult.valid();
  }

  /// Normalizes a local or already-prefixed phone number into E.164.
  static String normalizePhoneNumber({
    required String dialCode,
    required String nationalNumber,
    String? isoCode,
  }) {
    final input = nationalNumber.trim();
    final iso = isoCode == null ? null : _tryPhoneIsoCode(isoCode);

    if (iso != null && input.isNotEmpty) {
      try {
        return PhoneNumber.parse(input, destinationCountry: iso).international;
      } on PhoneNumberException {
        // Fall through to the simple E.164 normalizer so invalid input can
        // still be echoed as a corrected candidate in validation errors.
      }
    }

    final digits = nationalNumber.replaceAll(RegExp(r'\D'), '');
    final countryDigits = dialCode.replaceAll('+', '');
    final withoutLeadingZero = digits.replaceFirst(RegExp(r'^0+'), '');

    if (digits.startsWith(countryDigits)) {
      return '+$digits';
    }

    return '$dialCode$withoutLeadingZero';
  }

  /// Country-aware phone validation for picker-driven phone inputs.
  ///
  /// Returns the normalized E.164 value in [ValidationResult.correctedValue]
  /// when the input is valid.
  static ValidationResult validatePhoneNumberForCountry(
    String? value, {
    required String isoCode,
    required String dialCode,
    String? countryName,
    String? fieldName,
  }) {
    final input = value?.trim();
    final resolvedFieldName = fieldName ?? 'Phone number';

    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: resolvedFieldName,
      );
    }

    final iso = _tryPhoneIsoCode(isoCode);
    final digitsOnly = input.replaceAll(RegExp(r'\D'), '');
    final normalizedCandidate = normalizePhoneNumber(
      dialCode: dialCode,
      nationalNumber: input,
      isoCode: isoCode,
    );

    if (iso == null) {
      return ValidationResult.invalid(
        _config.messages.invalidPhone,
        field: resolvedFieldName,
        correctedValue: normalizedCandidate,
        metadata: {'isoCode': isoCode, 'dialCode': dialCode},
      );
    }

    if (dialCode == '+1') {
      final nanpDigits =
          digitsOnly.length == 11 && digitsOnly.startsWith('1')
              ? digitsOnly.substring(1)
              : digitsOnly;

      if (nanpDigits.length != 10) {
        return ValidationResult.invalid(
          _config.messages.phoneDigits.replaceFirst('{digits}', '10'),
          field: resolvedFieldName,
          correctedValue: normalizedCandidate,
          metadata: {
            'isoCode': isoCode,
            'dialCode': dialCode,
            'nationalDigits': nanpDigits,
          },
        );
      }

      return ValidationResult(
        isValid: true,
        correctedValue: '+1$nanpDigits',
        fieldName: resolvedFieldName,
        metadata: {
          'isoCode': isoCode,
          'dialCode': dialCode,
          'nationalDigits': nanpDigits,
        },
      );
    }

    try {
      final phoneNumber = PhoneNumber.parse(input, destinationCountry: iso);
      if (!phoneNumber.isValid()) {
        return ValidationResult.invalid(
          countryName == null
              ? _config.messages.invalidPhone
              : 'Enter a valid $countryName phone number.',
          field: resolvedFieldName,
          correctedValue: phoneNumber.international,
          metadata: {
            'isoCode': isoCode,
            'dialCode': dialCode,
            'nationalDigits': phoneNumber.nsn,
          },
        );
      }

      return ValidationResult(
        isValid: true,
        correctedValue: phoneNumber.international,
        fieldName: resolvedFieldName,
        metadata: {
          'isoCode': isoCode,
          'dialCode': dialCode,
          'nationalDigits': phoneNumber.nsn,
        },
      );
    } on PhoneNumberException {
      return ValidationResult.invalid(
        countryName == null
            ? _config.messages.invalidPhone
            : 'Enter a valid $countryName phone number.',
        field: resolvedFieldName,
        correctedValue: normalizedCandidate,
        metadata: {'isoCode': isoCode, 'dialCode': dialCode},
      );
    }
  }

  static IsoCode? _tryPhoneIsoCode(String isoCode) {
    try {
      return IsoCode.values.byName(isoCode.toUpperCase());
    } on ArgumentError {
      return null;
    }
  }

  /* ----------------------------- URL ----------------------------- */

  static ValidationResult validateUrl(
    String? value, {
    bool requireHttps = false,
    List<String> allowedSchemes = const ['http', 'https'],
    String? fieldName,
  }) {
    final input = value?.trim();
    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'URL',
      );
    }

    // Ensure scheme for parsing
    final hasScheme = RegExp(r'^[a-zA-Z]+://').hasMatch(input);
    final url = hasScheme ? input : 'https://$input';

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority) {
      return ValidationResult.invalid(
        _config.messages.invalidUrl,
        field: fieldName,
      );
    }

    // Scheme validation
    if (!allowedSchemes.contains(uri.scheme)) {
      return ValidationResult.invalid(
        _config.messages.urlScheme.replaceFirst(
          '{schemes}',
          allowedSchemes.join(' or '),
        ),
        field: fieldName,
      );
    }

    if (requireHttps && uri.scheme != 'https') {
      return ValidationResult.invalid(
        _config.messages.urlHttpsRequired,
        field: fieldName,
        correctedValue: url.replaceFirst('http://', 'https://'),
      );
    }

    // Domain validation
    if (!_isValidDomain(uri.host)) {
      return ValidationResult.invalid(
        _config.messages.urlDomain,
        field: fieldName,
      );
    }

    // Block private/loopback targets to prevent SSRF if the URL is ever fetched server-side.
    if (_isPrivateOrLoopback(uri.host)) {
      return ValidationResult.invalid(
        _config.messages.urlPublicAddress,
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- NAME ----------------------------- */

  static ValidationResult validateName(
    String? value, {
    String fieldName = 'Name',
    int minLength = 2,
    int? maxLength,
    bool allowNumbers = false,
    bool allowSpecialChars = false,
    List<String>? allowedSpecialChars,
  }) {
    final name = value?.trim();
    if (name == null || name.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required.replaceFirst('{field}', fieldName),
        field: fieldName,
      );
    }

    // Length validation
    if (name.length < minLength) {
      return ValidationResult.invalid(
        _config.messages.nameLength
            .replaceFirst('{field}', fieldName)
            .replaceFirst('2', minLength.toString()),
        field: fieldName,
      );
    }

    if (maxLength != null && name.length > maxLength) {
      return ValidationResult.invalid(
        _config.messages.nameMaxLength
            .replaceFirst('{field}', fieldName)
            .replaceFirst('{max}', maxLength.toString()),
        field: fieldName,
      );
    }

    // Character validation
    String allowedPattern = r'[a-zA-Z\s\-';
    if (allowNumbers) allowedPattern += '0-9';
    if (allowSpecialChars) {
      allowedPattern +=
          allowedSpecialChars?.join('') ?? r'!@#$%^&*()_+=\[\]{}:;"<>?/\\|`~';
    }
    allowedPattern += ']';

    final validCharsRegex = RegExp('^$allowedPattern+\$');
    if (!validCharsRegex.hasMatch(name)) {
      return ValidationResult.invalid(
        _config.messages.nameInvalidChars.replaceFirst('{field}', fieldName),
        field: fieldName,
      );
    }

    // Multiple spaces check
    if (_multipleSpacesRegex.hasMatch(name)) {
      return ValidationResult.invalid(
        _config.messages.nameMultipleSpaces.replaceFirst('{field}', fieldName),
        field: fieldName,
      );
    }

    // Trimmed name for consecutive special chars check
    final trimmedName = name.trim();
    if (RegExp(r'[\-\s]{2,}').hasMatch(trimmedName)) {
      return ValidationResult.invalid(
        _config.messages.nameConsecutiveChars.replaceFirst(
          '{field}',
          fieldName,
        ),
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- CREDIT CARD ----------------------------- */

  static ValidationResult validateCreditCard(
    String? value, {
    String? fieldName,
  }) {
    final input = value?.replaceAll(RegExp(r'\s'), '');
    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Credit card',
      );
    }

    if (!_creditCardRegex.hasMatch(input)) {
      return ValidationResult.invalid(
        _config.messages.creditCardFormat,
        field: fieldName,
      );
    }

    // Luhn algorithm check
    if (!_isValidLuhn(input)) {
      return ValidationResult.invalid(
        _config.messages.creditCardInvalid,
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- DATE ----------------------------- */

  static ValidationResult validateDate(
    DateTime? date, {
    DateTime? min,
    DateTime? max,
    bool allowFuture = false,
    bool allowPast = true,
    String? fieldName,
  }) {
    if (date == null) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Date',
      );
    }

    final now = DateTime.now();

    if (!allowFuture && date.isAfter(now)) {
      return ValidationResult.invalid(
        _config.messages.dateFutureNotAllowed,
        field: fieldName,
      );
    }

    if (!allowPast && date.isBefore(now)) {
      return ValidationResult.invalid(
        _config.messages.datePastNotAllowed,
        field: fieldName,
      );
    }

    if (min != null && date.isBefore(min)) {
      return ValidationResult.invalid(
        _config.messages.dateBeforeMin.replaceFirst(
          '{min}',
          DateFormat.yMd().format(min),
        ),
        field: fieldName,
      );
    }

    if (max != null && date.isAfter(max)) {
      return ValidationResult.invalid(
        _config.messages.dateAfterMax.replaceFirst(
          '{max}',
          DateFormat.yMd().format(max),
        ),
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- POSTAL CODE ----------------------------- */

  static ValidationResult validatePostalCode(
    String? value, {
    String countryCode = 'US',
    String? fieldName,
  }) {
    final input = value?.trim();
    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'Postal code',
      );
    }

    switch (countryCode.toUpperCase()) {
      case 'US':
        if (!_postalCodeRegex.hasMatch(input)) {
          return ValidationResult.invalid(
            _config.messages.postalCodeZip,
            field: fieldName,
          );
        }
        break;
      case 'CA':
        if (!RegExp(r'^[A-Za-z]\d[A-Za-z][ -]?\d[A-Za-z]\d$').hasMatch(input)) {
          return ValidationResult.invalid(
            _config.messages.postalCodeCanadian,
            field: fieldName,
          );
        }
        break;
      default:
        // Generic validation for other countries
        if (input.length < 3 || input.length > 10) {
          return ValidationResult.invalid(
            _config.messages.postalCodeGeneric,
            field: fieldName,
          );
        }
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- SOCIAL SECURITY NUMBER ----------------------------- */

  static ValidationResult validateSSN(String? value, {String? fieldName}) {
    final input = value?.trim();
    if (input == null || input.isEmpty) {
      return ValidationResult.invalid(
        _config.messages.required,
        field: fieldName ?? 'SSN',
      );
    }

    if (!_ssnRegex.hasMatch(input)) {
      return ValidationResult.invalid(
        _config.messages.ssnFormat,
        field: fieldName,
      );
    }

    // Check for invalid SSN ranges
    final parts = input.split('-');
    final area = parts[0];
    final group = parts[1];
    final serial = parts[2];

    // No SSNs with 000 in any segment
    if (area == '000' || group == '00' || serial == '0000') {
      return ValidationResult.invalid(
        _config.messages.ssnInvalid,
        field: fieldName,
      );
    }

    // No SSNs with 666 as area number
    if (area == '666') {
      return ValidationResult.invalid(
        _config.messages.ssnInvalid,
        field: fieldName,
      );
    }

    // No SSNs from 987-65-4320 to 987-65-4329 (advertising)
    if (area == '987' && group == '65' && serial.startsWith('432')) {
      return ValidationResult.invalid(
        _config.messages.ssnInvalid,
        field: fieldName,
      );
    }

    return ValidationResult.valid();
  }

  /* ----------------------------- COMPOSITE VALIDATORS ----------------------------- */

  static ValidationResult validateMultiple(
    String? value,
    List<ValidationResult Function(String?)> validators,
  ) {
    for (final validator in validators) {
      final result = validator(value);
      if (!result.isValid) {
        return result;
      }
    }
    return ValidationResult.valid();
  }

  static ValidationResult validateAll(
    Map<String, ValidationResult Function()> validators,
  ) {
    for (final entry in validators.entries) {
      final result = entry.value();
      if (!result.isValid) {
        return result;
      }
    }
    return ValidationResult.valid();
  }

  /* ----------------------------- INPUT FORMATTERS ----------------------------- */

  static TextInputFormatter get emailFormatter =>
      FilteringTextInputFormatter.deny(RegExp(r'\s'));

  static TextInputFormatter get phoneFormatter =>
      FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]'));

  static TextInputFormatter numberFormatter({
    bool decimal = true,
    bool allowNegative = false,
  }) {
    final pattern = StringBuffer(r'[');
    pattern.write(r'\d');
    if (decimal) pattern.write('.');
    if (allowNegative) pattern.write('-');
    pattern.write(']');

    return FilteringTextInputFormatter.allow(RegExp(pattern.toString()));
  }

  static TextInputFormatter get nameFormatter =>
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-]'));

  static TextInputFormatter get creditCardFormatter =>
      FilteringTextInputFormatter.allow(RegExp(r'[\d\s]'));

  static TextInputFormatter lengthLimitingFormatter(
    int maxLength, {
    bool enforceMaxLength = true,
  }) {
    return LengthLimitingTextInputFormatter(
      enforceMaxLength ? maxLength : null,
    );
  }

  /* ----------------------------- HELPER METHODS ----------------------------- */

  static bool _isValidLuhn(String number) {
    int sum = 0;
    bool alternate = false;

    for (int i = number.length - 1; i >= 0; i--) {
      int digit = int.tryParse(number[i]) ?? 0;

      if (alternate) {
        digit *= 2;
        if (digit > 9) {
          digit = (digit % 10) + 1;
        }
      }

      sum += digit;
      alternate = !alternate;
    }

    return (sum % 10) == 0;
  }

  static bool _hasRepeatingCharacters(String input) {
    return RegExp(r'(.)\1{2,}').hasMatch(input);
  }

  static bool _isSequential(String input) {
    // Check for sequential numbers (123, 456, etc.)
    if (RegExp(
      r'123|234|345|456|567|678|789|890|987|876|765|654|543|432|321|210',
    ).hasMatch(input)) {
      return true;
    }

    // Check for sequential letters (abc, def, etc.)
    final lowercase = input.toLowerCase();
    return RegExp(
      r'abc|bcd|cde|def|efg|fgh|ghi|hij|ijk|jkl|klm|lmn|mno|nop|opq|pqr|qrs|rst|stu|tuv|uvw|vwx|wxy|xyz',
    ).hasMatch(lowercase);
  }

  static bool _isPrivateOrLoopback(String host) {
    const blocked = {'localhost', '127.0.0.1', '::1', '0.0.0.0'};
    if (blocked.contains(host.toLowerCase())) return true;
    final parts = host.split('.');
    if (parts.length == 4) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == 10) return true;
      if (a == 172 && b != null && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
    }
    return false;
  }

  static bool _isValidDomain(String domain) {
    if (domain.isEmpty || domain.length > 253) return false;

    // Check each label
    final labels = domain.split('.');
    if (labels.length < 2) return false;

    for (final label in labels) {
      if (label.isEmpty || label.length > 63) return false;
      if (!RegExp(
        r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$',
      ).hasMatch(label)) {
        return false;
      }
      if (label.startsWith('-') || label.endsWith('-')) return false;
    }

    return true;
  }

  static String _formatPhoneNumber(String digits, String countryCode) {
    switch (countryCode.toUpperCase()) {
      case 'US':
      case 'CA':
        if (digits.length == 10) {
          return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
        }
        break;
    }
    return digits;
  }

  /* ----------------------------- CONVENIENCE METHODS ----------------------------- */

  /// Quick validation for TextFormField
  static String? Function(String?) textFieldValidator({
    required ValidationResult Function(String?) validator,
    String? fieldName,
  }) {
    return (value) => validator(value).toErrorString();
  }

  /// Batch validation of multiple fields
  static Map<String, ValidationResult> validateForm({
    required Map<String, String?> fields,
    required Map<String, ValidationResult Function(String?)> validators,
  }) {
    final results = <String, ValidationResult>{};

    for (final entry in fields.entries) {
      final fieldName = entry.key;
      final value = entry.value;
      final validator = validators[fieldName];

      if (validator != null) {
        results[fieldName] = validator(value);
      }
    }

    return results;
  }

  /// Check if all validation results are valid
  static bool isFormValid(Map<String, ValidationResult> results) {
    return results.values.every((result) => result.isValid);
  }

  /// Get all error messages from validation results
  static List<String> getErrorMessages(Map<String, ValidationResult> results) {
    return results.values
        .where((result) => !result.isValid)
        .map((result) => result.errorMessage!)
        .toList();
  }
}

/* ----------------------------- EXTENSIONS ----------------------------- */

extension StringValidationExtensions on String {
  ValidationResult validateEmail({EmailValidationOptions? options}) =>
      ValidationUtils.validateEmail(
        this,
        options: options ?? const EmailValidationOptions(),
      );

  ValidationResult validatePassword({PasswordRequirements? requirements}) =>
      ValidationUtils.validatePassword(
        this,
        requirements: requirements ?? const PasswordRequirements(),
      );

  ValidationResult validatePhoneNumber({String? countryCode}) =>
      ValidationUtils.validatePhoneNumber(this, countryCode: countryCode);

  ValidationResult validateUrl({bool requireHttps = false}) =>
      ValidationUtils.validateUrl(this, requireHttps: requireHttps);

  ValidationResult validateName({String fieldName = 'Name'}) =>
      ValidationUtils.validateName(this, fieldName: fieldName);

  ValidationResult validateCreditCard() =>
      ValidationUtils.validateCreditCard(this);

  ValidationResult validatePostalCode({String countryCode = 'US'}) =>
      ValidationUtils.validatePostalCode(this, countryCode: countryCode);

  ValidationResult validateSSN() => ValidationUtils.validateSSN(this);
}

extension DateTimeValidationExtensions on DateTime {
  ValidationResult validateDate({
    DateTime? min,
    DateTime? max,
    bool allowFuture = false,
  }) => ValidationUtils.validateDate(
    this,
    min: min,
    max: max,
    allowFuture: allowFuture,
  );
}
