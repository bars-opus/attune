// Spec 2 §3.2 D7 (Step 6 of 12): two questions, both required; two toggles;
// no option to seek parents (10 S22).
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

class DatingChildrenStep extends ConsumerStatefulWidget {
  const DatingChildrenStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingChildrenStep> createState() => _DatingChildrenStepState();
}

class _DatingChildrenStepState extends ConsumerState<DatingChildrenStep>
    with DatingStepState<DatingChildrenStep> {
  bool? _have;
  String? _want;
  bool _mustMatch = false;
  bool _excludeParents = false;

  @override
  void resetAnswers() {
    _have = null;
    _want = null;
    _mustMatch = false;
    _excludeParents = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    // Each answer only where the person hasn't changed it (T6 fix 2).
    if (!isTouched('have')) _have = p.childrenHave;
    if (!isTouched('want')) _want = p.childrenWant;
    if (!isTouched('mustMatch')) _mustMatch = p.wantMustMatch;
    if (!isTouched('excludeParents')) _excludeParents = p.excludeParents;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final have = _have;
    final want = _want;
    return DatingStepFrame(
      step: 'children',
      title: loc.dating_childrenTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profileFailed)
            DatingLoadError(busy: profileRetrying, onRetry: retryProfile),
          DatingChoiceGroup<bool>(
            label: loc.dating_childrenHaveQ,
            options: [(true, loc.dating_yes), (false, loc.dating_no)],
            value: have,
            onChanged: (v) => answer(['have'], () => _have = v),
          ),
          const SizedBox(height: Spacing.md),
          DatingChoiceGroup<String>(
            label: loc.dating_childrenWantQ,
            options: [
              ('yes', loc.dating_yes),
              ('no', loc.dating_no),
              ('open', loc.dating_openToIt),
            ],
            value: want,
            onChanged: (v) => answer(['want'], () => _want = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_childrenMustMatch),
            value: _mustMatch,
            onChanged: (v) => answer(['mustMatch'], () => _mustMatch = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_childrenExcludeParents),
            value: _excludeParents,
            onChanged:
                (v) => answer(['excludeParents'], () => _excludeParents = v),
          ),
          Text(
            loc.dating_childrenHelper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        // Never over saved answers the screen couldn't read (T6 fix 2).
        onPressed:
            online && profileReady && have != null && want != null
                ? () => write(
                  'd7',
                  [have, want, _mustMatch, _excludeParents],
                  (key) => ref
                      .read(datingSetupGatewayProvider)
                      .saveChildren(
                        key,
                        have: have,
                        want: want,
                        mustMatch: _mustMatch,
                        excludeParents: _excludeParents,
                      ),
                  (w) => widget.nav.next(w.nextStep ?? 'faith'),
                )
                : null,
      ),
    );
  }
}
