import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';


class AuthUIService {
  final BuildContext context;
  final WidgetRef ref;
  late final AppLocalizations loc;

  AuthUIService(this.context, this.ref) {
    loc = AppLocalizations.of(context)!;
  }

  // ==================== VALIDATION METHODS ====================

  String? validateEmail(String? email) {
    final result = ValidationUtils.validateEmail(
      email,
      options: const EmailValidationOptions(
        checkDisposableDomains: true,
        allowPlusAlias: true,
      ),
    );
    return result.toErrorString();
  }

  String? validatePassword(String? password) {
    final result = ValidationUtils.validatePassword(
      password,
      requirements: PasswordRequirements.medium,
    );
    return result.toErrorString();
  }

  String? validateConfirmPassword(String? password, String? confirm) {
    if (confirm == null || confirm.isEmpty) {
      return loc.commonPasswordConfirmRequired;
    }
    if (password != confirm) {
      return loc.commonPasswordsDoNotMatch;
    }
    return null;
  }

  // ==================== AUTH METHODS ====================

  Future<AuthResult> loginWithEmail({
    required String email,
    required String password,
    String? successRoute = '/home',
    String? loadingMessage,
    String? successMessage,
  }) async {
    // On login only validate email format — never validate password strength,
    // which would block users whose passwords predate the current requirements.
    final emailError = validateEmail(email);
    if (emailError != null) {
      context.showErrorSnackbar(emailError);
      return AuthResult.failure(emailError);
    }

    if (password.isEmpty) {
      context.showErrorSnackbar(loc.authPasswordRequired);
      return AuthResult.failure(loc.authPasswordRequired);
    }

    _showLoading(loadingMessage ?? loc.loggingInIndicatorText);

    try {
      final authOps = ref.read(authOperationsProvider);
      await authOps.signInWithEmail(email.trim(), password);

      _hideLoading();
      _showSuccess(successMessage ?? loc.loginSuccessful);
      // GoRouter's redirect handles navigation once the auth state fires —
      // no explicit context.go needed (consistent with Google/Apple sign-in).
      return AuthResult.success();
    } on AuthException catch (error) {
      _hideLoading();
      _showErrorWithRetry(
        message: error.message,
        retryAction:
            () => loginWithEmail(
              email: email,
              password: password,
              successRoute: successRoute,
            ),
      );
      return AuthResult.failure(error.message);
    } catch (error, stackTrace) {
      _hideLoading();
      _logError('Login failed', error, stackTrace);
      _showErrorWithRetry(
        message: '${loc.errorLoginFailed}: ${_getUserFriendlyError(error)}',
        retryAction:
            () => loginWithEmail(
              email: email,
              password: password,
              successRoute: successRoute,
            ),
      );
      return AuthResult.failure(_getUserFriendlyError(error));
    }
  }

  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String confirmPassword,
    Map<String, dynamic>? userMetadata,
    String? successRoute = '/home',
    String? verificationRoute = '/createUsername',
  }) async {
    // Validate all fields
    final errors =
        [
          validateEmail(email),
          validatePassword(password),
          validateConfirmPassword(password, confirmPassword),
        ].where((e) => e != null).toList();

    if (errors.isNotEmpty) {
      context.showErrorSnackbar(errors.first!);

      return AuthResult.failure(errors.first!);
    }
    _showLoading(loc.authCreatingAccount);
    try {
      final authOps = ref.read(authOperationsProvider);

      // ✅ NOW this returns AuthResponse, not void!
      final response = await authOps.signUpWithEmail(email.trim(), password);

      _hideLoading();

      // ✅ Check if user is auto-logged in (session exists)
      if (response.session != null && response.user != null) {
        debugPrint('✅ Email confirmation OFF - user auto-logged in');
        debugPrint('👤 User ID: ${response.user!.id}');
        debugPrint('🔐 Session: ${response.session != null}');

        _showSuccess(loc.authAccountCreatedSuccess);

        if (context.mounted) {
          _safeNavigate('/createUsername');
        }
        return AuthResult.success();
      }
      // ✅ Email confirmation ON
      else {
        _showSuccess(loc.authCheckEmailToConfirm);

        if (context.mounted) {
          _safeNavigate('/verifyEmail', extra: email.trim());
        }
        return AuthResult.success(requiresEmailVerification: true);
      }
    } on AuthException catch (error) {
      _hideLoading();
      _showErrorWithRetry(
        message: error.message,
        retryAction:
            () => signUpWithEmail(
              email: email,
              password: password,
              confirmPassword: confirmPassword,
              userMetadata: userMetadata,
            ),
      );
      return AuthResult.failure(error.message);
    } catch (error, stackTrace) {
      _hideLoading();
      _logError('Signup failed', error, stackTrace);
      _showErrorWithRetry(
        message: loc.authSignUpFailed(_getUserFriendlyError(error)),
        retryAction:
            () => signUpWithEmail(
              email: email,
              password: password,
              confirmPassword: confirmPassword,
              userMetadata: userMetadata,
            ),
      );
      return AuthResult.failure(_getUserFriendlyError(error));
    }
  }

  // In your AuthService class, use _supabase (not Supabase.instance.client)
  Future<AuthResult> signInWithGoogle() async {
    // Native iOS: blocking call — show loading like Apple Sign-In.
    // Android/Web: opens browser and returns immediately — no spinner.
    final isNative = !kIsWeb && (Platform.isIOS || Platform.isMacOS);
    if (isNative) _showLoading(loc.authSigningInWithGoogle);

    try {
      final authOps = ref.read(authOperationsProvider);
      await authOps.signInWithGoogle();
      _hideLoading();
      return AuthResult.success();
    } on AuthException catch (error) {
      _hideLoading();
      _showErrorWithRetry(
        message: error.message,
        retryAction: signInWithGoogle,
      );
      return AuthResult.failure(error.message);
    } catch (error, stackTrace) {
      _hideLoading();
      // Silently swallow user-cancelled errors
      final msg = error.toString().toLowerCase();
      if (msg.contains('cancel') ||
          msg.contains('sign_in_canceled') ||
          msg.contains('sign_in_failed')) {
        return AuthResult.failure('cancelled');
      }
      _logError('Google sign-in failed', error, stackTrace);
      _showErrorWithRetry(
        message: loc.authGoogleSignInFailed(_getUserFriendlyError(error)),
        retryAction: signInWithGoogle,
      );
      return AuthResult.failure(_getUserFriendlyError(error));
    }
  }

  Future<AuthResult> signInWithApple() async {
    _showLoading(loc.authAuthenticatingWithApple);

    try {
      final authOps = ref.read(authOperationsProvider);
      await authOps.signInWithApple();
      // Native Apple sign-in completes synchronously (no browser redirect).
      // Hide the loading indicator; auth state stream triggers navigation.
      _hideLoading();
      return AuthResult.success();
    } on AuthException catch (error) {
      _hideLoading();
      _showErrorWithRetry(message: error.message, retryAction: signInWithApple);
      return AuthResult.failure(error.message);
    } catch (error, stackTrace) {
      _hideLoading();
      _logError('Apple sign-in failed', error, stackTrace);
      // Silently swallow user-cancelled errors — no snackbar needed
      if (error.toString().contains('canceled') ||
          error.toString().contains('cancelled')) {
        return AuthResult.failure('cancelled');
      }
      _showErrorWithRetry(
        message: loc.authAppleSignInFailed(_getUserFriendlyError(error)),
        retryAction: signInWithApple,
      );
      return AuthResult.failure(_getUserFriendlyError(error));
    }
  }

  Future<AuthResult> resetPassword(String email) async {
    final emailError = validateEmail(email);
    if (emailError != null) {
      context.showErrorSnackbar(emailError);

      return AuthResult.failure(emailError);
    }

    _showLoading(loc.authSendingResetEmail);

    try {
      final authService = ref.read(authServiceProvider);
      await authService.resetPassword(email.trim());

      _hideLoading();
      _showSuccess(loc.authResetEmailSent);
      return AuthResult.success();
    } on AuthException catch (error) {
      _hideLoading();
      _showErrorWithRetry(
        message: error.message,
        retryAction: () => resetPassword(email),
      );
      return AuthResult.failure(error.message);
    } catch (error, stackTrace) {
      _hideLoading();
      _logError('Password reset failed', error, stackTrace);
      _showErrorWithRetry(
        message: loc.authPasswordResetFailed(_getUserFriendlyError(error)),
        retryAction: () => resetPassword(email),
      );
      return AuthResult.failure(_getUserFriendlyError(error));
    }
  }

  // ==================== UI HELPERS ====================

  void _showLoading(String message) {
    if (context.mounted) {
      context.showLoadingSnackbar( message);
      
    }
  }

  void _hideLoading() {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  void _showSuccess(String message) {
    if (context.mounted) {
      context.showSuccessSnackbar(backgroundColor: Colors.green, message);
      
    }
  }

  void _showErrorWithRetry({
    required String message,
    required VoidCallback retryAction,
  }) {
    if (context.mounted) {
      context.showErrorSnackbar(
       message,
        onAction: retryAction,
      );
     
    }
  }

  void _safeNavigate(String route, {Object? extra}) {
    if (!context.mounted) return;
    // No post-frame needed here because you're already in an async callback
    context.go(route, extra: extra);
  }
  // ==================== ERROR HANDLING ====================

  void _logError(String message, Object error, StackTrace stackTrace) {
    // In production, send to crash reporting service (Sentry, Firebase Crashlytics)
    debugPrint('🚨 $message: $error\n$stackTrace');
  }

  String _getUserFriendlyError(Object error) {
    if (error is AuthException) return error.message;

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('socket')) {
      return loc.errorNetwork;
    }

    if (errorString.contains('timeout')) {
      return loc.errorParsingSubtitle('credentials');
    }

    return loc.errorClientSubtitle;
  }

  // ==================== NAVIGATION HELPERS ====================

  void navigateToHome() => _safeNavigate('/home');
  void navigateToLogin() => _safeNavigate('/login');
  void navigateToSignUp() => _safeNavigate('/signup');
  void navigateToForgotPassword() => _safeNavigate('/forgot-password');
  void navigateToVerifyEmail({String? email}) {
    _safeNavigate('/verify-email', extra: email);
  }
}

// ==================== SUPPORTING CLASSES ====================

/// Result of authentication operations for better type safety
class AuthResult {
  final bool isSuccess;
  final String? errorMessage;
  final bool requiresEmailVerification;
  final Map<String, dynamic> metadata;

  const AuthResult._({
    required this.isSuccess,
    this.errorMessage,
    this.requiresEmailVerification = false,
    this.metadata = const {},
  });

  factory AuthResult.success({
    bool requiresEmailVerification = false,
    Map<String, dynamic> metadata = const {},
  }) {
    return AuthResult._(
      isSuccess: true,
      requiresEmailVerification: requiresEmailVerification,
      metadata: metadata,
    );
  }

  factory AuthResult.failure(
    String errorMessage, {
    Map<String, dynamic> metadata = const {},
  }) {
    return AuthResult._(
      isSuccess: false,
      errorMessage: errorMessage,
      metadata: metadata,
    );
  }
}
