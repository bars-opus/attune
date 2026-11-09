// Spec 2 §3.2 D11 (Step 10 of 12): the shell until W4a builds §3.3's flow
// (R-26). The intro copy is §3.3.2's; Continue opens D12.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DatingVerifyStep extends StatelessWidget {
  const DatingVerifyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return DatingStepFrame(
      step: 'verify',
      title: loc.dating_verifyTitle,
      onBack: nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_verifyBody, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_verifyLater, style: theme.textTheme.bodyMedium),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: () => nav.next('preview'),
      ),
    );
  }
}
