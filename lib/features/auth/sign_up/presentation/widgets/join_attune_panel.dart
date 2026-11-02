import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/welcome_screen.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

/// G2 · the guest's sign-in tab under flow_signin_v2 (Spec 1 §3.2): "Join
/// Attune" and the three ways in. Back from the first sign-up step returns
/// to this tab (`/home?tab=chat`, Spec 1 W3a).
class JoinAttunePanel extends StatelessWidget {
  const JoinAttunePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return AllowLargeText(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Gap(Spacing.lg.h),
          Semantics(
            header: true,
            child: Text(
              loc.flow_joinTitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Gap(Spacing.md.h),
          Text(
            loc.flow_joinBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          Gap(Spacing.lg.h),
          FlowPrimaryButton(
            label: loc.flow_welcomeGetStarted,
            onPressed:
                () => context.go(
                  WelcomeScreen.signUpLocation(
                    'new',
                    back: homeLocation(tab: AppTab.chat),
                  ),
                ),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveAccount,
            onPressed:
                () => context.go(
                  WelcomeScreen.signUpLocation(
                    'returning',
                    back: homeLocation(tab: AppTab.chat),
                  ),
                ),
          ),
          const Gap(Spacing.sm),
          FlowSecondaryButton(
            label: loc.flow_welcomeHaveInvite,
            onPressed: () => context.go(RouteNames.invite),
          ),
        ],
      ),
    );
  }
}
