// lib/core/auth/auth_exceptions.dart
class AuthException implements Exception {
  final String message;
  final String? statusCode;
  final String? originalMessage;

  AuthException(
    this.message, {
    this.statusCode,
    this.originalMessage,
  });

  @override
  String toString() {
    if (statusCode != null) {
      return '[$statusCode] $message';
    }
    return message;
  }
}

// Extension to convert Supabase AuthException to our custom one
extension SupabaseAuthExceptionExtension on AuthException {
  AuthException toCustomAuthException() {
    return AuthException(
      message,
      statusCode: statusCode,
      originalMessage: message,
    );
  }
}
