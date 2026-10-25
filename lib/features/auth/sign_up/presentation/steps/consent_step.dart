import 'dart:async';

import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/submit_once.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A5 · Before you start (EULA v2), and A5c "We've updated our terms" for
/// an account that accepted an older version (Spec 1 §3.3, §3.15). Never
/// animated. Bullet 2 is checked against the live AI features by the owner
/// and privacy counsel before production (W2 gate).
class ConsentStep extends StatefulWidget {
  const ConsentStep({
    super.key,
    required this.onAgree,
    required this.onNotNow,
    this.updatedTerms = false,
    this.busy = false,
    this.errorText,
  });

  /// Each keeps the step busy until it has finished.
  final FutureOr<void> Function() onAgree;
  final FutureOr<void> Function() onNotNow;
  final bool updatedTerms;
  final bool busy;
  final String? errorText;

  @override
  State<ConsentStep> createState() => _ConsentStepState();
}

class _ConsentStepState extends State<ConsentStep> with SubmitOnce {
  bool get _busy => widget.busy || submitting;

  /// Agree or Not now, once, however fast either is pressed. Progress
  /// shows on the button that was pressed ([tag]).
  void _run(FutureOr<void> Function() action, Symbol tag) {
    if (_busy) return;
    submitOnce(action, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final errorText = widget.errorText;
    Widget bullet(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Text('•  ', style: theme.textTheme.bodyLarge),
          ),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
    return FlowFrame(
      title:
          widget.updatedTerms
              ? loc.flow_consentUpdatedTitle
              : loc.flow_consentTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bullet(loc.flow_consentAdults),
          bullet(loc.flow_consentAi),
          bullet(loc.flow_consentData),
          Wrap(
            children: [
              FlowTextLink(
                label: loc.flow_consentTermsLink,
                onPressed: () => showTermsSheet(context),
              ),
              FlowTextLink(
                label: loc.flow_consentPrivacyLink,
                onPressed: () => showPrivacySheet(context),
              ),
              FlowTextLink(
                label: loc.flow_consentAiLink,
                onPressed:
                    () => BottomSheetUtils.showDocumentationBottomSheet(
                      context: context,
                      widget: DocumentationTabView(
                        module: AboutAttuneDocs(),
                        showDocumentationFirst: true,
                      ),
                    ),
              ),
            ],
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
          label: loc.flow_consentAgree,
          busy: runningTag == #agree,
          onPressed: _busy ? null : () => _run(widget.onAgree, #agree),
        ),
        FlowSecondaryButton(
          label: loc.flow_consentNotNow,
          busy: runningTag == #notNow,
          onPressed: _busy ? null : () => _run(widget.onNotNow, #notNow),
        ),
      ],
    );
  }
}
