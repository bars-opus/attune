// lib/core/services/username_service.dart

import 'package:attune/features/profile/repositories/profile_repository_interface.dart';

/// A pure service class for username validation and operations
/// No Flutter dependencies - can be used in any layer (providers, repositories, use cases)
class UsernameService {
  final ProfileRepository _repository;

  UsernameService({required ProfileRepository repository})
    : _repository = repository;

  /// Validates username format without checking availability
  /// Returns ValidationResult with error message if invalid
  ValidationResult validateUsername(String username) {
    if (username.isEmpty) {
      return ValidationResult.invalid('Username cannot be empty');
    }

    if (username.length < 3) {
      return ValidationResult.invalid('Username must be at least 3 characters');
    }

    if (username.length > 30) {
      return ValidationResult.invalid(
        'Username must be less than 30 characters',
      );
    }

    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      return ValidationResult.invalid(
        'Only letters, numbers, and underscores allowed',
      );
    }

    if (RegExp(r'^[0-9_]').hasMatch(username)) {
      return ValidationResult.invalid(
        'Username cannot start with number or underscore',
      );
    }

    return ValidationResult.valid();
  }

  /// Checks if username is available (not taken)
  Future<bool> isUsernameAvailable(String username) async {
    // First validate format
    final validation = validateUsername(username);
    if (!validation.isValid) {
      return false;
    }

    // Then check with repository
    return await _repository.isUsernameAvailable(username);
  }

  /// Comprehensive validation including availability check
  /// Use this when you need both format and availability in one call
  Future<ValidationResult> validateUsernameWithAvailability(
    String username,
  ) async {
    // Format validation first
    final formatValidation = validateUsername(username);
    if (!formatValidation.isValid) {
      return formatValidation;
    }

    // Check availability
    try {
      final isAvailable = await _repository.isUsernameAvailable(username);
      if (!isAvailable) {
        return ValidationResult.invalid('Username is already taken');
      }
      return ValidationResult.valid();
    } catch (e) {
      return ValidationResult.invalid('Error checking username availability');
    }
  }

  /// Sanitize username (remove special characters, lowercase, etc.)
  String sanitizeUsername(String username) {
    return username
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '') // Remove invalid chars
        .trim();
  }
}

/// Simple validation result class
class ValidationResult {
  final bool isValid;
  final String? errorMessage;

  const ValidationResult._({required this.isValid, this.errorMessage});

  factory ValidationResult.valid() => const ValidationResult._(isValid: true);

  factory ValidationResult.invalid(String message) {
    return ValidationResult._(isValid: false, errorMessage: message);
  }
}
