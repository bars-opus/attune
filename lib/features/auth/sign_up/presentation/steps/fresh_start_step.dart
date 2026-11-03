import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/phone_entry.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// DM2 · One more code to finish (Spec 1 §3.5, W6a): after "I'm new to
/// Attune" parked the old account, a new code to the same number makes a
/// new account. Never animated (§2.2).
class FreshStartStep extends StatefulWidget {
  const FreshStartStep({
    super.key,
    required this.phoneE164,
    required this.onSend,
    this.errorText,
    this.errorCount = 0,
  });

  final String phoneE164;

  /// "Send code"; the step stays busy until it has finished.
  final FutureOr<void> Function() onSend;

  /// The code couldn't be sent; raise [errorCount] to read it again.
  final String? errorText;
  final int errorCount;

  @override
  State<FreshStartStep> createState() => _FreshStartStepState();
}

class _FreshStartStepState extends State<FreshStartStep> with SubmitOnce {
  @override
  void didUpdateWidget(covariant FreshStartStep oldWidget) {
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
      title: loc.flow_freshStartTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.flow_freshStartBody(formatPhoneForDisplay(widget.phoneE164)),
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
          label: loc.flow_freshStartSend,
          busy: submitting,
          onPressed: submitting ? null : () => submitOnce(widget.onSend),
        ),
      ],
    );
  }
}
