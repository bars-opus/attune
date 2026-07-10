// Create a model class
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';

// 1. Update model to accept context
class AuthButtonConfig {
  final String label;
  final IconData icon;
  final IconData prefixIcon;
  final String from;

  final void Function(BuildContext context) onPressed;

  const AuthButtonConfig({
    required this.label,
    required this.icon,
    this.from = '',
    required this.onPressed,
    required this.prefixIcon,
  });
}

// 2. Define buttons (no context yet)

List<AuthButtonConfig> getAuthButtons(
  AppLocalizations loc,
  String from,
  WidgetRef ref, // Add this parameter
) {
  final isLoading = ref.watch(isLoadingProvider);

  return [
    AuthButtonConfig(
      label: from == 'Register' ? loc.appleRegister : loc.appleSignIn,
      icon: FontAwesomeIcons.apple,
      prefixIcon: Icons.open_in_new_rounded,
      onPressed:
          isLoading
              ? (context) {}
              : (context) async {
                final authUI = AuthUIService(context, ref);
                await authUI.signInWithApple();
              },
    ),
    AuthButtonConfig(
      label:
          from == 'Register'
              ? loc.googleRegister
              : loc.googleSignIn, // Fixed typo
      icon: FontAwesomeIcons.google,
      prefixIcon: Icons.open_in_new_rounded,
      onPressed:
          isLoading
              ? (context) {}
              : (context) async {
                final authUI = AuthUIService(context, ref);
                await authUI.signInWithGoogle();
              },
    ),
    AuthButtonConfig(
      label: loc.emailAndPassword,
      prefixIcon: FontAwesomeIcons.angleUp,
      icon: Icons.email,
      onPressed: (context) {
        BottomSheetUtils.showDocumentationBottomSheet(
          context: context,
          widget: LoginScreen(),
        );
      },
    ),
  ];
}
