// Spec 2 §3.2 D6 (Step 5 of 12; §2.4). Off-country: no choice ("You'll be
// introduced to men."), the line and Why?. On-country: Men / Women /
// Everyone (the explicit full set), "Only you can see this." The ages:
// 18-99, defaulted by the server (18-20: up to own age + 7), a two-thumb
// slider read as "Youngest {n}" and "Oldest {n}" with increase/decrease.
// The country note first when the phone country is Tier 1/2 and the
// choice includes the person's own gender, or the person is non-binary.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/country_note_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const datingEveryone = ['man', 'non_binary', 'woman'];

const _minAge = 18;
const _maxAge = 99;

class DatingMeetStep extends ConsumerStatefulWidget {
  const DatingMeetStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingMeetStep> createState() => _DatingMeetStepState();
}

class _DatingMeetStepState extends ConsumerState<DatingMeetStep>
    with DatingStepState<DatingMeetStep> {
  String? _seek;
  RangeValues? _ages;

  /// The country note is up (one at a time, however fast the taps).
  bool _noting = false;

  @override
  void resetAnswers() {
    _seek = null;
    _ages = null;
    _noting = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    if (!isTouched('seek')) {
      final s = [...p.seeking]..sort();
      // Only a set this screen can show is shown; anything else is asked
      // again rather than widened or narrowed unseen.
      _seek =
          s.length == 1 && (s.single == 'man' || s.single == 'woman')
              ? s.single
              : listEquals(s, datingEveryone)
              ? 'everyone'
              : null;
    }
    if (!isTouched('ages') && p.minAge != null && p.maxAge != null) {
      _ages = RangeValues(p.minAge!.toDouble(), p.maxAge!.toDouble());
    }
  }

  Future<void> _continue(
    String? identity,
    bool sameGender,
    String? noteCountry,
    RangeValues ages,
  ) async {
    if (identity == null || _noting || saving) return;
    final seeking =
        sameGender
            ? (_seek == 'everyone' ? datingEveryone : [_seek!])
            : [identity == 'woman' ? 'man' : 'woman'];
    final ownIncluded = identity == 'non_binary' || seeking.contains(identity);
    if (noteCountry != null && sameGender && ownIncluded) {
      final account = ref.read(datingAccountProvider);
      setState(() => _noting = true);
      final choice = await showDatingCountryNote(context, country: noteCountry);
      if (!mounted) return;
      setState(() => _noting = false);
      // D8: a note answered for the last account saves nothing for the next.
      if (choice != DatingNoteChoice.save ||
          ref.read(datingAccountProvider) != account) {
        return;
      }
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    final min = ages.start.round();
    final max = ages.end.round();
    await write(
      'd6',
      [seeking, min, max],
      (key) => gateway.saveWhoToMeet(
        key,
        seeking: seeking,
        minAge: min,
        maxAge: max,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'children'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final profile = watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final account = ref.watch(datingAccountProvider);
    final listsRead = ref.watch(datingSetupListsProvider(account));
    // A failed read shows nothing of an old value (carry C, D8).
    final lists = listsRead.hasError ? null : listsRead.valueOrNull;
    final known = lists != null && profileReady;
    final country = profile?.countryCode;
    final identity = profile?.identity;
    final sameGender = lists?.country(country)?.sameGender ?? false;
    final defaults = lists?.defaultAges ?? (_minAge, _maxAge);
    final ages =
        _ages ?? RangeValues(defaults.$1.toDouble(), defaults.$2.toDouble());
    final min = ages.start.round();
    final max = ages.end.round();
    final theme = Theme.of(context);
    void step(bool young, int by) => answer(['ages'], () {
      final lo = young ? (min + by).clamp(_minAge, max) : min;
      final hi = young ? max : (max + by).clamp(min, _maxAge);
      _ages = RangeValues(lo.toDouble(), hi.toDouble());
    });
    // Off-country only Woman or Man can be introduced (§2.4).
    final plain = identity == 'woman' || identity == 'man';
    final ready =
        online &&
        known &&
        identity != null &&
        (sameGender ? _seek != null : plain);
    return DatingStepFrame(
      step: 'meet',
      title: loc.dating_meetTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (listsRead.hasError || profileFailed)
            DatingLoadError(
              busy: listsRead.isLoading || profileRetrying,
              onRetry: () {
                if (listsRead.hasError) {
                  ref.invalidate(datingSetupListsProvider(account));
                }
                if (profileFailed) retryProfile();
              },
            ),
          if (known && !sameGender) ...[
            if (plain)
              Text(
                identity == 'man'
                    ? loc.dating_offMeetWomen
                    : loc.dating_offMeetMen,
                style: theme.textTheme.titleMedium,
              ),
            if (country != null) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                plain
                    ? loc.dating_offMeetLine(datingCountryName(loc, country))
                    : loc.dating_offCountryLine(
                      datingCountryName(loc, country),
                    ),
                style: theme.textTheme.bodyMedium,
              ),
              FlowTextLink(
                label: loc.dating_why,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => showDatingWhySheet(context, country: country),
              ),
            ],
          ] else if (sameGender) ...[
            DatingChoiceGroup<String>(
              label: loc.dating_meetTitle,
              // The screen title already asks it (T6 fix 1, I-2).
              showLabel: false,
              options: [
                ('man', loc.dating_seekMen),
                ('woman', loc.dating_seekWomen),
                ('everyone', loc.dating_seekEveryone),
              ],
              value: _seek,
              onChanged: (v) => answer(['seek'], () => _seek = v),
            ),
            Text(loc.dating_meetPrivate, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: Spacing.lg),
          Text(loc.dating_ages(min, max), style: theme.textTheme.titleSmall),
          ExcludeSemantics(
            child: RangeSlider(
              min: _minAge.toDouble(),
              max: _maxAge.toDouble(),
              divisions: _maxAge - _minAge,
              values: ages,
              onChanged: (v) => answer(['ages'], () => _ages = v),
            ),
          ),
          Row(
            children: [
              for (final (young, name, text) in [
                (
                  true,
                  loc.dating_agesYoungestLabel,
                  loc.dating_agesYoungest(min),
                ),
                (false, loc.dating_agesOldestLabel, loc.dating_agesOldest(max)),
              ])
                Expanded(
                  child: _AgeEnd(
                    name: name,
                    text: text,
                    value: young ? min : max,
                    // Youngest stays at or under oldest, both in 18-99.
                    canIncrease: young ? min < max : max < _maxAge,
                    canDecrease: young ? min > _minAge : max > min,
                    onStep: (by) => step(young, by),
                  ),
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
        busy: saving || _noting,
        onPressed:
            ready
                ? () => _continue(identity, sameGender, lists.noteCountry, ages)
                : null,
      ),
    );
  }
}

/// One end of the age range as an adjustable (pre-flight I-12): its name
/// ("Youngest") and value (the age, read once: fix 1, M-2), the values a
/// step up or down reaches, and only the steps it can take. The slider
/// itself is excluded, so this is what is read; [text] is what is seen.
class _AgeEnd extends StatelessWidget {
  const _AgeEnd({
    required this.name,
    required this.text,
    required this.value,
    required this.canIncrease,
    required this.canDecrease,
    required this.onStep,
  });

  final String name;
  final String text;
  final int value;
  final bool canIncrease;
  final bool canDecrease;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => Semantics(
    label: name,
    value: '$value',
    increasedValue: canIncrease ? '${value + 1}' : null,
    decreasedValue: canDecrease ? '${value - 1}' : null,
    onIncrease: canIncrease ? () => onStep(1) : null,
    onDecrease: canDecrease ? () => onStep(-1) : null,
    child: ExcludeSemantics(
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    ),
  );
}
