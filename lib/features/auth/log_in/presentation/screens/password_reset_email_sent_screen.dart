import 'package:attune/features/auth/utility/auth_exports.dart';

class PasswordResetEmailSentScreen extends StatelessWidget {
  final String email;

  const PasswordResetEmailSentScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.neutral,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: AppIconButton(
          icon: Icons.close,
          onPressed: () => context.go(RouteNames.home),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: Spacing.md),
        children: [
          Gap(Spacing.md),
          IconAvatar(
            icon: Icons.mark_email_unread_outlined,
            iconColor: colorScheme.primary,
            size: 100,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            avatarRadiusSize: 100,
            circularRadius: 100.r,
          ),
          Gap(Spacing.lg),
          Text(
            loc.authPasswordResetSentTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.md),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: loc.authPasswordResetSentBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                TextSpan(
                  text: email,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.lg),
          AppButton(
            elevation: 0,
            height: 40.h,
            label: loc.authBackToSignIn,
            onPressed: () => context.go(RouteNames.login),
            textColor: colorScheme.onSurface,
            padding: Spacing.horizontalMd,
            size: ButtonSize.small,
            width: double.infinity,
            customColor: colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          Gap(Spacing.lg),
          Text(
            loc.authPasswordResetSentNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
          Gap(Spacing.md),
        ],
      ),
    );
  }
}
