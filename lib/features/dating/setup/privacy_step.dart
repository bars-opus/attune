// Spec 2 §3.2 D4 (Step 3 of 12; consent; no motion): five headed blocks,
// the consent with its full sentence, the Dating terms and privacy links
// (Spec 1's sheets, R-31). "Agree and continue": three consent events
// (dating-2.0) and the enrolment. Disabled offline.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingPrivacyStep extends ConsumerStatefulWidget {
  const DatingPrivacyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPrivacyStep> createState() => _DatingPrivacyStepState();
}

class _DatingPrivacyStepState extends ConsumerState<DatingPrivacyStep>
    with DatingStepState<DatingPrivacyStep> {
  bool _agreed = false;

  @override
  void resetAnswers() => _agreed = false;

  @override
  void seedAnswers(DatingMyProfile profile) {}

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    Widget block(String head, String body) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(head, style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: Spacing.xs),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    return DatingStepFrame(
      step: 'privacy',
      title: loc.dating_privacyTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(loc.dating_privacyWhyHead, loc.dating_privacyWhy),
          block(loc.dating_privacyWhoHead, loc.dating_privacyWho),
          block(loc.dating_privacyNeverHead, loc.dating_privacyNever),
          block(loc.dating_privacyProtectedHead, loc.dating_privacyProtected),
          block(loc.dating_privacyLeavingHead, loc.dating_privacyLeaving),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_privacyConsent),
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
          ),
          FlowTextLink(
            label: loc.dating_datingTerms,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => showTermsSheet(context),
          ),
          FlowTextLink(
            label: loc.dating_privacyNotice,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => showPrivacySheet(context),
          ),
          if (refusal != null) datingRefusalLine(loc, refusal!),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_agreeContinue,
        busy: saving,
        onPressed:
            online && _agreed
                ? () => write(
                  'd4',
                  'agree',
                  (key) =>
                      ref.read(datingSetupGatewayProvider).agreeAndBegin(key),
                  (w) => widget.nav.next(w.nextStep ?? 'you'),
                )
                : null,
      ),
    );
  }
}
