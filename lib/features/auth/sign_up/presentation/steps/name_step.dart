import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/display_name_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A1 · Your name (Spec 1 §3.3).
class NameStep extends StatefulWidget {
  const NameStep({
    super.key,
    required this.onSubmit,
    required this.onBack,
    this.initialName,
  });

  final String? initialName;

  /// The normalised name. The step stays busy until it has finished.
  final FutureOr<void> Function(String name) onSubmit;
  final VoidCallback onBack;

  @override
  State<NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<NameStep> with SubmitOnce {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  DisplayNameError? _error;

  /// One per failed submit, so the same message is read out again.
  int _errorCount = 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    // Done on the keyboard and Continue together run this once.
    if (submitting) return;
    final error = validateDisplayName(_name.text);
    setState(() {
      _error = error;
      if (error != null) _errorCount++;
    });
    if (error != null) return;
    final name = normalizeDisplayName(_name.text);
    submitOnce(() => widget.onSubmit(name));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_nameTitle,
      hint: loc.flow_nameHint,
      onBack: widget.onBack,
      body: FlowTextField(
        controller: _name,
        label: loc.flow_nameLabel,
        errorText: switch (_error) {
          DisplayNameError.needsLetter => loc.flow_nameNeedsLetter,
          DisplayNameError.tooLong => loc.flow_nameTooLong,
          null => null,
        },
        errorCount: _errorCount,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.givenName],
        onSubmitted: (_) => _continue(),
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.flow_continue,
          busy: submitting,
          onPressed: _continue,
        ),
      ],
    );
  }
}
