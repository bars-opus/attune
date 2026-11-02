import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// X1 · Attune is for adults (Spec 1 §3.6). Never animated: the route opens
/// with no transition and nothing on it moves. No retry, no hint of the
/// cut-off. [serverRefused] is the variant after complete_sign_up refused
/// (`signup:not_eligible`): the client has already signed out.
class UnderAgeStopScreen extends StatelessWidget {
  const UnderAgeStopScreen({
    super.key,
    this.serverRefused = false,
    this.accountHeld = false,
  });

  final bool serverRefused;

  /// Spec 1 W3a: the catch-up date of birth of an existing account was
  /// under 18; the account is on hold and the client has signed out.
  final bool accountHeld;

  /// Before W7's country list: the international helpline directory.
  static const youthSupportUrl = 'https://findahelpline.com';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final body =
        accountHeld
            ? loc.flow_ageStopAccountBody
            : serverRefused
            ? '${loc.flow_ageStopServerLead} ${loc.flow_ageStopBody}'
            : loc.flow_ageStopBody;
    return FlowFrame(
      title: loc.flow_ageStopTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          FlowTextLink(
            label: loc.flow_ageStopYouthLink,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => UrlLauncherUtils.launchUrlWithFeedback(
                  context: context,
                  url: youthSupportUrl,
                ),
          ),
        ],
      ),
      actions: [
        FlowSecondaryButton(
          label: loc.flow_close,
          onPressed: () => context.go(RouteNames.welcome),
        ),
      ],
    );
  }
}
