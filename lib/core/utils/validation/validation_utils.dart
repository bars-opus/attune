// lib/core/utils/validation_utils.dart
/// Configuration for validation rules and messages
class ValidationConfig {
  final String languageCode;
  final ValidationMessages messages;

  ValidationConfig({this.languageCode = 'en', ValidationMessages? messages})
    : messages = messages ?? ValidationMessages();

  factory ValidationConfig.en() => ValidationConfig(languageCode: 'en');

  factory ValidationConfig.es() =>
      ValidationConfig(languageCode: 'es', messages: ValidationMessages.es());
}

/// Localized validation messages
class ValidationMessages {
  final String required;
  final String invalidEmail;
  final String disposableEmail;
  final String emailTooLong;
  final String emailLocalPartTooLong;
  final String passwordLength;
  final String passwordMaxLength;
  final String passwordUppercase;
  final String passwordLowercase;
  final String passwordDigit;
  final String passwordSpecialChar;
  final String weakPassword;
  final String passwordRepeatingChars;
  final String passwordSequential;
  final String invalidPhone;
  final String phoneDigits;
  final String phoneUK;
  final String invalidUrl;
  final String urlHttpsRequired;
  final String urlScheme;
  final String urlDomain;
  final String urlPublicAddress;
  final String nameLength;
  final String nameMaxLength;
  final String nameInvalidChars;
  final String nameMultipleSpaces;
  final String nameConsecutiveChars;
  final String invalidNumber;
  final String numberMin;
  final String numberMax;
  final String creditCardFormat;
  final String creditCardInvalid;
  final String dateFutureNotAllowed;
  final String datePastNotAllowed;
  final String dateBeforeMin;
  final String dateAfterMax;
  final String postalCodeZip;
  final String postalCodeCanadian;
  final String postalCodeGeneric;
  final String ssnFormat;
  final String ssnInvalid;

  ValidationMessages({
    String? required,
    String? invalidEmail,
    String? disposableEmail,
    String? emailTooLong,
    String? emailLocalPartTooLong,
    String? passwordLength,
    String? passwordMaxLength,
    String? passwordUppercase,
    String? passwordLowercase,
    String? passwordDigit,
    String? passwordSpecialChar,
    String? weakPassword,
    String? passwordRepeatingChars,
    String? passwordSequential,
    String? invalidPhone,
    String? phoneDigits,
    String? phoneUK,
    String? invalidUrl,
    String? urlHttpsRequired,
    String? urlScheme,
    String? urlDomain,
    String? urlPublicAddress,
    String? nameLength,
    String? nameMaxLength,
    String? nameInvalidChars,
    String? nameMultipleSpaces,
    String? nameConsecutiveChars,
    String? invalidNumber,
    String? numberMin,
    String? numberMax,
    String? creditCardFormat,
    String? creditCardInvalid,
    String? dateFutureNotAllowed,
    String? datePastNotAllowed,
    String? dateBeforeMin,
    String? dateAfterMax,
    String? postalCodeZip,
    String? postalCodeCanadian,
    String? postalCodeGeneric,
    String? ssnFormat,
    String? ssnInvalid,
  }) : required = required ?? 'This field is required',
       invalidEmail = invalidEmail ?? 'Please enter a valid email address',
       disposableEmail =
           disposableEmail ?? 'Please use a permanent email address',
       emailTooLong = emailTooLong ?? 'Email is too long (max 254 characters)',
       emailLocalPartTooLong =
           emailLocalPartTooLong ?? 'Local part of email is too long',
       passwordLength =
           passwordLength ?? 'Password must be at least {length} characters',
       passwordMaxLength =
           passwordMaxLength ?? 'Password must be at most {max} characters',
       passwordUppercase =
           passwordUppercase ??
           'Password must include at least one uppercase letter',
       passwordLowercase =
           passwordLowercase ??
           'Password must include at least one lowercase letter',
       passwordDigit =
           passwordDigit ?? 'Password must include at least one number',
       passwordSpecialChar =
           passwordSpecialChar ??
           'Password must include at least one special character',
       weakPassword = weakPassword ?? 'This password is too common',
       passwordRepeatingChars =
           passwordRepeatingChars ??
           'Password contains too many repeating characters',
       passwordSequential =
           passwordSequential ?? 'Password contains sequential characters',
       invalidPhone = invalidPhone ?? 'Please enter a valid phone number',
       phoneDigits = phoneDigits ?? 'Phone number must be {digits} digits',
       phoneUK = phoneUK ?? 'Invalid UK phone number',
       invalidUrl = invalidUrl ?? 'Please enter a valid URL',
       urlHttpsRequired = urlHttpsRequired ?? 'URL must start with https://',
       urlScheme = urlScheme ?? 'URL must start with {schemes}',
       urlDomain = urlDomain ?? 'Invalid domain name',
       urlPublicAddress =
           urlPublicAddress ?? 'URL must point to a public address',
       nameLength = nameLength ?? '{field} must be at least 2 characters',
       nameMaxLength =
           nameMaxLength ?? '{field} must be at most {max} characters',
       nameInvalidChars =
           nameInvalidChars ??
           '{field} can only contain letters, spaces, and hyphens',
       nameMultipleSpaces =
           nameMultipleSpaces ?? '{field} cannot contain multiple spaces',
       nameConsecutiveChars =
           nameConsecutiveChars ??
           '{field} cannot contain consecutive hyphens or spaces',
       invalidNumber = invalidNumber ?? 'Please enter a valid number',
       numberMin = numberMin ?? '{field} must be at least {min}',
       numberMax = numberMax ?? '{field} must be at most {max}',
       creditCardFormat =
           creditCardFormat ?? 'Please enter a valid credit card number',
       creditCardInvalid = creditCardInvalid ?? 'Invalid credit card number',
       dateFutureNotAllowed =
           dateFutureNotAllowed ?? 'Date cannot be in the future',
       datePastNotAllowed = datePastNotAllowed ?? 'Date cannot be in the past',
       dateBeforeMin = dateBeforeMin ?? 'Date must be after {min}',
       dateAfterMax = dateAfterMax ?? 'Date must be before {max}',
       postalCodeZip =
           postalCodeZip ??
           'Please enter a valid ZIP code (e.g., 12345 or 12345-6789)',
       postalCodeCanadian =
           postalCodeCanadian ??
           'Please enter a valid Canadian postal code (e.g., A1A 1A1)',
       postalCodeGeneric =
           postalCodeGeneric ?? 'Please enter a valid postal code',
       ssnFormat = ssnFormat ?? 'Please enter a valid SSN (e.g., 123-45-6789)',
       ssnInvalid = ssnInvalid ?? 'Invalid SSN';

  factory ValidationMessages.es() => ValidationMessages(
    required: 'Este campo es requerido',
    invalidEmail: 'Por favor ingresa un correo válido',
    disposableEmail: 'Por favor usa un correo electrónico permanente',
    emailTooLong:
        'El correo electrónico es demasiado largo (máx. 254 caracteres)',
    emailLocalPartTooLong:
        'La parte local del correo electrónico es demasiado larga',
    passwordLength: 'La contraseña debe tener al menos {length} caracteres',
    passwordMaxLength: 'La contraseña debe tener como máximo {max} caracteres',
    passwordUppercase:
        'La contraseña debe incluir al menos una letra mayúscula',
    passwordLowercase:
        'La contraseña debe incluir al menos una letra minúscula',
    passwordDigit: 'La contraseña debe incluir al menos un número',
    passwordSpecialChar:
        'La contraseña debe incluir al menos un carácter especial',
    weakPassword: 'Esta contraseña es demasiado común',
    passwordRepeatingChars:
        'La contraseña contiene demasiados caracteres repetidos',
    passwordSequential: 'La contraseña contiene caracteres secuenciales',
    invalidPhone: 'Por favor ingresa un número de teléfono válido',
    phoneDigits: 'El número de teléfono debe tener {digits} dígitos',
    phoneUK: 'Número de teléfono británico inválido',
    invalidUrl: 'Por favor ingresa una URL válida',
    urlHttpsRequired: 'La URL debe comenzar con https://',
    urlScheme: 'La URL debe comenzar con {schemes}',
    urlDomain: 'Nombre de dominio inválido',
    urlPublicAddress: 'La URL debe apuntar a una dirección pública',
    nameLength: '{field} debe tener al menos 2 caracteres',
    nameMaxLength: '{field} debe tener como máximo {max} caracteres',
    nameInvalidChars: '{field} solo puede contener letras, espacios y guiones',
    nameMultipleSpaces: '{field} no puede contener múltiples espacios',
    nameConsecutiveChars:
        '{field} no puede contener guiones o espacios consecutivos',
    invalidNumber: 'Por favor ingresa un número válido',
    numberMin: '{field} debe ser al menos {min}',
    numberMax: '{field} debe ser como máximo {max}',
    creditCardFormat:
        'Por favor ingresa un número de tarjeta de crédito válido',
    creditCardInvalid: 'Número de tarjeta de crédito inválido',
    dateFutureNotAllowed: 'La fecha no puede ser futura',
    datePastNotAllowed: 'La fecha no puede ser en el pasado',
    dateBeforeMin: 'La fecha debe ser después de {min}',
    dateAfterMax: 'La fecha debe ser antes de {max}',
    postalCodeZip:
        'Por favor ingresa un código postal válido (ej. 12345 o 12345-6789)',
    postalCodeCanadian:
        'Por favor ingresa un código postal canadiense válido (ej. A1A 1A1)',
    postalCodeGeneric: 'Por favor ingresa un código postal válido',
    ssnFormat: 'Por favor ingresa un SSN válido (ej. 123-45-6789)',
    ssnInvalid: 'SSN inválido',
  );
}

/// Password validation requirements
class PasswordRequirements {
  final int minLength;
  final int? maxLength;
  final bool requireUppercase;
  final bool requireLowercase;
  final bool requireDigits;
  final bool requireSpecialChars;
  final List<String>? customDisallowedPasswords;
  final bool checkCommonPasswords;

  const PasswordRequirements({
    this.minLength = 8,
    this.maxLength,
    this.requireUppercase = true,
    this.requireLowercase = true,
    this.requireDigits = true,
    this.requireSpecialChars = false,
    this.customDisallowedPasswords,
    this.checkCommonPasswords = true,
  });

  /// Strong password requirements (recommended)
  static const strong = PasswordRequirements(
    minLength: 12,
    requireUppercase: true,
    requireLowercase: true,
    requireDigits: true,
    requireSpecialChars: true,
    checkCommonPasswords: true,
  );

  /// Medium password requirements
  static const medium = PasswordRequirements(
    minLength: 8,
    requireUppercase: true,
    requireLowercase: true,
    requireDigits: true,
    requireSpecialChars: false,
  );

  /// Basic password requirements
  static const basic = PasswordRequirements(
    minLength: 6,
    requireUppercase: false,
    requireLowercase: true,
    requireDigits: true,
    requireSpecialChars: false,
  );
}

/// Email validation configuration
class EmailValidationOptions {
  final bool checkDisposableDomains;
  final List<String> additionalDisposableDomains;
  final bool allowPlusAlias;
  final RegExp? customEmailRegex;

  const EmailValidationOptions({
    this.checkDisposableDomains = true,
    this.additionalDisposableDomains = const [],
    this.allowPlusAlias = true,
    this.customEmailRegex,
  });
}
