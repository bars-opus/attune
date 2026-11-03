import 'dart:async';

import 'package:attune/core/utils/constants.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// DM1 · Welcome (Spec 1 §3.5, W6a): the number's account has had no
/// activity for 180 days. Nothing about that account is shown: no name, no
/// path, no partner, no dates. Never animated (§2.2). "Used Attune before
/// on this number?" goes to support, which never confirms or denies an
/// account.
class DormantStep extends StatefulWidget {
  const DormantStep({
    super.key,
    required this.onNew,
    this.errorText,
    this.errorCount = 0,
  });

  /// "I'm new to Attune"; the step stays busy until it has finished.
  final FutureOr<void> Function() onNew;

  /// The fresh start couldn't run; raise [errorCount] to read it again.
  final String? errorText;
  final int errorCount;

  @override
  State<DormantStep> createState() => _DormantStepState();
}

class _DormantStepState extends State<DormantStep> with SubmitOnce {
  @override
  void didUpdateWidget(covariant DormantStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    final error = widget.errorText;
    if (error != null &&
        (error != oldWidget.errorText ||
            widget.errorCount != oldWidget.errorCount)) {
      SemanticsService.announce(error, Directionality.of(context));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final errorText = widget.errorText;
    return FlowFrame(
      title: loc.flow_dormantTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.flow_dormantBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            FlowErrorLine(
              text: errorText,
              style: theme.textTheme.bodyMedium,
              liveRegion: true,
            ),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_dormantNew,
          busy: submitting,
          onPressed: submitting ? null : () => submitOnce(widget.onNew),
        ),
        FlowTextLink(
          label: loc.flow_dormantUsedBefore,
          onPressed:
              () => UrlLauncherUtils.launchEmail(
                context: context,
                email: AppConstants.supportEmail,
              ),
        ),
      ],
    );
  }
}
