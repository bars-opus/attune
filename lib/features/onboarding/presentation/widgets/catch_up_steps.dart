import 'dart:async';

import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// H1 · Account check (Spec 1 §3.15): any hold. No reason, no motion.
/// W6a reuses it for the hook's `account_review`.
class AccountHoldStep extends StatefulWidget {
  const AccountHoldStep({super.key, required this.onSignOut});

  final FutureOr<void> Function() onSignOut;

  @override
  State<AccountHoldStep> createState() => _AccountHoldStepState();
}

class _AccountHoldStepState extends State<AccountHoldStep> with SubmitOnce {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_holdTitle,
      body: Text(
        loc.flow_holdBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_holdContact,
          onPressed:
              () => UrlLauncherUtils.launchEmail(
                context: context,
                email: AppConstants.supportEmail,
              ),
        ),
        FlowSecondaryButton(
          label: loc.flow_signOut,
          busy: submitting,
          onPressed: () => submitOnce(widget.onSignOut),
        ),
      ],
    );
  }
}

/// A need this build doesn't know (HomeNeed.unknown, a later wave added
/// it): the account is never treated as complete, so the person is asked
/// to update the app (W2 final review M-5).
class UpdateAppStep extends StatefulWidget {
  const UpdateAppStep({super.key, required this.onSignOut});

  final FutureOr<void> Function() onSignOut;

  @override
  State<UpdateAppStep> createState() => _UpdateAppStepState();
}

class _UpdateAppStepState extends State<UpdateAppStep> with SubmitOnce {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_updateTitle,
      body: Text(
        loc.flow_updateBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowSecondaryButton(
          label: loc.flow_signOut,
          busy: submitting,
          onPressed: () => submitOnce(widget.onSignOut),
        ),
      ],
    );
  }
}

/// The account couldn't be read and nothing on the phone says where it
/// stands: try again, or sign out.
class CheckOfflineStep extends StatefulWidget {
  const CheckOfflineStep({
    super.key,
    required this.onRetry,
    required this.onSignOut,
  });

  final FutureOr<void> Function() onRetry;
  final FutureOr<void> Function() onSignOut;

  @override
  State<CheckOfflineStep> createState() => _CheckOfflineStepState();
}

class _CheckOfflineStepState extends State<CheckOfflineStep> with SubmitOnce {
  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FlowFrame(
      title: loc.flow_checkOfflineTitle,
      body: Text(
        loc.flow_checkOfflineBody,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_tryAgain,
          busy: submitting && runningTag == #retry,
          onPressed: () => submitOnce(widget.onRetry, tag: #retry),
        ),
        FlowSecondaryButton(
          label: loc.flow_signOut,
          onPressed: () => submitOnce(widget.onSignOut, tag: #signOut),
        ),
      ],
    );
  }
}
