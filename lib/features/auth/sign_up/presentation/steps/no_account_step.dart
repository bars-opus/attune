import 'dart:async';

import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// N1 · No account (Spec 1 §3.4): said only after the code proved the
/// number (10 F-10).
class NoAccountStep extends StatefulWidget {
  const NoAccountStep({
    super.key,
    required this.onCreate,
    required this.onOtherNumber,
    this.errorText,
  });

  /// Each keeps the step busy until it has finished.
  final FutureOr<void> Function() onCreate;
  final FutureOr<void> Function() onOtherNumber;

  /// "Use a different number" couldn't sign out (review B5 M-5).
  final String? errorText;

  @override
  State<NoAccountStep> createState() => _NoAccountStepState();
}

class _NoAccountStepState extends State<NoAccountStep> with SubmitOnce {
  /// One of the two, once, however fast either is pressed. Progress shows
  /// on the button that was pressed ([tag]).
  void _run(FutureOr<void> Function() action, Symbol tag) {
    if (submitting) return;
    submitOnce(action, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final errorText = widget.errorText;
    final body = Text(
      loc.flow_noAccountBody,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
    );
    return FlowFrame(
      title: loc.flow_noAccountTitle,
      body:
          errorText == null
              ? body
              : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  body,
                  const SizedBox(height: 12),
                  FlowErrorLine(
                    text: errorText,
                    style: theme.textTheme.bodyMedium,
                    liveRegion: true,
                  ),
                ],
              ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_noAccountCreate,
          busy: runningTag == #create,
          onPressed: submitting ? null : () => _run(widget.onCreate, #create),
        ),
        FlowSecondaryButton(
          label: loc.flow_noAccountOtherNumber,
          busy: runningTag == #otherNumber,
          onPressed:
              submitting
                  ? null
                  : () => _run(widget.onOtherNumber, #otherNumber),
        ),
      ],
    );
  }
}

/// "Welcome back, {name}." for a second, then home (spec §3.3 A4). Up
/// too briefly for a screen reader to reach the title, so it is read out
/// once it appears (review B4 M-5).
class WelcomeBackStep extends StatefulWidget {
  const WelcomeBackStep({super.key, required this.firstName});

  final String? firstName;

  @override
  State<WelcomeBackStep> createState() => _WelcomeBackStepState();
}

class _WelcomeBackStepState extends State<WelcomeBackStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.announce(
        _title(AppLocalizations.of(context)!),
        Directionality.of(context),
      );
    });
  }

  String _title(AppLocalizations loc) {
    final name = widget.firstName;
    return name == null || name.isEmpty
        ? loc.flow_welcomeBackNoName
        : loc.flow_welcomeBack(name);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(title: _title(loc), body: const SizedBox.shrink());
  }
}
