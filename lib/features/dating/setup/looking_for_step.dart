// Spec 2 §3.2 D2 (Step 1 of 12): intention, the marriage timeline, the
// attestation (asked again whenever intention or marriage history change),
// separated-but-not-divorced, married before (optional). §3.15: the
// timeline expands over 200 ms (none with reduce motion); the attestation's
// error is a live region.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingLookingForStep extends ConsumerStatefulWidget {
  const DatingLookingForStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingLookingForStep> createState() =>
      _DatingLookingForStepState();
}

class _DatingLookingForStepState extends ConsumerState<DatingLookingForStep>
    with DatingStepState<DatingLookingForStep> {
  String? _intention;
  String? _timeline;
  bool _timelineVisible = true;
  bool _attested = false;
  bool _attestError = false;
  String? _marital;
  bool _maritalVisible = false;
  bool _marriedOpen = false;

  /// Rebuilds "Married before?" open when a saved answer arrives (fix 2).
  int _marriedSeeds = 0;

  @override
  void resetAnswers() {
    _intention = null;
    _timeline = null;
    _timelineVisible = true;
    _attested = false;
    _attestError = false;
    _marital = null;
    _maritalVisible = false;
    _marriedOpen = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    if (!isTouched('intention')) _intention = p.intention;
    if (!isTouched('timeline')) _timeline = p.marriageTimeline;
    if (!isTouched('timelineVisible')) _timelineVisible = p.timelineVisible;
    if (!isTouched('marital') && p.marital != null) {
      _marital = p.marital;
      _marriedOpen = true;
      _marriedSeeds++;
    }
    if (!isTouched('maritalVisible')) _maritalVisible = p.maritalVisible;
    if (!isTouched('attested')) _attested = p.attested;
  }

  /// An intention or marriage-history answer: the attestation is asked
  /// again, so it counts as changed too.
  void _changed(List<String> fields, VoidCallback change) =>
      answer([...fields, 'attested'], () {
        change();
        // §3.2 D2: any change to intention or marriage history asks again.
        _attested = false;
      });

  void _continue() {
    final intention = _intention;
    if (intention == null) return;
    if (!_attested) {
      setState(() => _attestError = true);
      return;
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd2',
      [intention, _timeline, _timelineVisible, _marital, _maritalVisible],
      (key) => gateway.saveIntention(
        key,
        intention: intention,
        timeline: intention == 'marriage' ? _timeline : null,
        timelineVisible: _timelineVisible,
        marital: _marital,
        maritalVisible: _maritalVisible,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'where'),
    );
  }

  Future<void> _separated() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (sheet) => AllowLargeText(
          child: SafeArea(
            // Scrolls at large text sizes (§3.0).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(sheet)!.dating_separatedSheet,
                    style: Theme.of(sheet).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Spacing.lg),
                  FlowSecondaryButton(
                    label: AppLocalizations.of(sheet)!.dating_close,
                    onPressed: () => Navigator.of(sheet).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    return DatingStepFrame(
      step: 'looking-for',
      title: loc.dating_lookingTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (profileFailed)
            DatingLoadError(busy: profileRetrying, onRetry: retryProfile),
          DatingChoiceGroup<String>(
            label: loc.dating_lookingTitle,
            // I-2: the screen title already asks it.
            showLabel: false,
            options: [
              ('marriage', loc.dating_intentMarriage),
              ('committed', loc.dating_intentCommitted),
              ('companionship', loc.dating_intentCompanionship),
              ('not_sure', loc.dating_intentNotSure),
            ],
            value: _intention,
            onChanged: (v) => _changed(['intention'], () => _intention = v),
          ),
          AnimatedSize(
            duration:
                reduceMotionOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
            child:
                _intention != 'marriage'
                    ? const SizedBox(width: double.infinity)
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: Spacing.md),
                        DatingChoiceGroup<String>(
                          label: loc.dating_timelineQ,
                          options: [
                            ('within_two_years', loc.dating_timelineSoon),
                            ('few_years', loc.dating_timelineFew),
                            ('no_set_time', loc.dating_timelineNone),
                          ],
                          value: _timeline,
                          onChanged:
                              (v) => answer(['timeline'], () => _timeline = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(loc.dating_timelineShow),
                          value: _timelineVisible,
                          onChanged:
                              (v) => answer([
                                'timelineVisible',
                              ], () => _timelineVisible = v),
                        ),
                      ],
                    ),
          ),
          const SizedBox(height: Spacing.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_attestation),
            value: _attested,
            onChanged:
                (v) => answer(['attested'], () {
                  _attested = v ?? false;
                  if (_attested) _attestError = false;
                }),
          ),
          Text(
            loc.dating_attestationHelper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_attestError) ...[
            const SizedBox(height: Spacing.xs),
            FlowErrorLine(text: loc.dating_attestationError, liveRegion: true),
          ],
          FlowTextLink(
            label: loc.dating_separatedLink,
            alignment: AlignmentDirectional.centerStart,
            onPressed: _separated,
          ),
          ExpansionTile(
            key: ValueKey(_marriedSeeds),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _marriedOpen,
            title: Text(loc.dating_marriedBefore),
            onExpansionChanged: (v) => _marriedOpen = v,
            children: [
              DatingChoiceGroup<String>(
                label: loc.dating_marriedBefore,
                // I-2: the tile's title already asks it.
                showLabel: false,
                options: [
                  ('never', loc.dating_maritalNever),
                  ('divorced', loc.dating_maritalDivorced),
                  ('widowed', loc.dating_maritalWidowed),
                ],
                value: _marital,
                onChanged: (v) => _changed(['marital'], () => _marital = v),
                // M-4: optional, so it can be taken back.
                onCleared:
                    () => _changed(['marital', 'maritalVisible'], () {
                      _marital = null;
                      _maritalVisible = false;
                    }),
              ),
              if (_marital == 'divorced' || _marital == 'widowed')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.dating_maritalShow),
                  value: _maritalVisible,
                  onChanged:
                      (v) =>
                          answer(['maritalVisible'], () => _maritalVisible = v),
                ),
            ],
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
        // M-3: not over saved answers the screen couldn't read.
        onPressed:
            online && _intention != null && profileReady ? _continue : null,
      ),
    );
  }
}
