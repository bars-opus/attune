import 'dart:async';

import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// The account behind a proven number is read before the flow goes on
/// (review B5 I-1, I-2). While that runs it says so; when it can't run
/// (offline) it says so in its own words, with "Try again" and "Not now"
/// (review B5 fix round 2). Nothing here is about a code.
class AccountCheckStep extends StatefulWidget {
  const AccountCheckStep({
    super.key,
    required this.checking,
    required this.onRetry,
    required this.onNotNow,
    this.failCount = 0,
    this.errorText,
  });

  /// The first check is running: progress, no buttons.
  final bool checking;

  /// Raise on each failed check: the failure is read out again.
  final int failCount;

  /// Each keeps the step busy until it has finished.
  final FutureOr<void> Function() onRetry;
  final FutureOr<void> Function() onNotNow;

  /// "Not now" couldn't sign out.
  final String? errorText;

  @override
  State<AccountCheckStep> createState() => _AccountCheckStepState();
}

class _AccountCheckStepState extends State<AccountCheckStep> with SubmitOnce {
  Timer? _slow;
  bool _showProgress = false;

  @override
  void initState() {
    super.initState();
    if (widget.checking) {
      _armProgress();
    } else {
      // Opened on a failure (A4's code was accepted, the account unread).
      WidgetsBinding.instance.addPostFrameCallback((_) => _announce());
    }
  }

  @override
  void didUpdateWidget(covariant AccountCheckStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.checking && !oldWidget.checking) _armProgress();
    if (!widget.checking) {
      _slow?.cancel();
      _showProgress = false;
      if (oldWidget.checking || widget.failCount > oldWidget.failCount) {
        _announce();
      }
    }
  }

  @override
  void dispose() {
    _slow?.cancel();
    super.dispose();
  }

  /// Any wait over 400 ms says what is happening (§2.2).
  void _armProgress() {
    _slow?.cancel();
    _slow = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _showProgress = true);
    });
  }

  void _announce() {
    if (!mounted) return;
    SemanticsService.announce(
      AppLocalizations.of(context)!.flow_accountCheckFailedBody,
      Directionality.of(context),
    );
  }

  void _run(FutureOr<void> Function() action, Symbol tag) {
    if (submitting || widget.checking) return;
    submitOnce(action, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );
    final errorText = widget.errorText;
    if (widget.checking) {
      return FlowFrame(
        title: loc.flow_accountChecking,
        body:
            _showProgress
                ? LinearProgressIndicator(
                  color: flowAccent(context),
                  semanticsLabel: loc.flow_accountChecking,
                )
                : const SizedBox(height: 4),
      );
    }
    return FlowFrame(
      title: loc.flow_accountCheckFailedTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Read out by [_announce] on each failure, so not a live region
          // too (it would be read twice).
          FlowErrorLine(text: loc.flow_accountCheckFailedBody, style: style),
          if (errorText != null) ...[
            const SizedBox(height: 12),
            FlowErrorLine(text: errorText, style: style, liveRegion: true),
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_tryAgain,
          busy: runningTag == #retry,
          onPressed: submitting ? null : () => _run(widget.onRetry, #retry),
        ),
        FlowSecondaryButton(
          label: loc.flow_consentNotNow,
          busy: runningTag == #notNow,
          onPressed: submitting ? null : () => _run(widget.onNotNow, #notNow),
        ),
      ],
    );
  }
}
