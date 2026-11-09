// Spec 2 §3.2 D8 (Step 7 of 12; optional): the Dating country's own list; a
// Christian choice opens "Denomination (optional)"; with a faith chosen the
// importance and the faith consent are required; visibility off by
// default. Skip (bottom-left) stores nothing: it is the never-gated clear
// (R-21).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingFaithStep extends ConsumerStatefulWidget {
  const DatingFaithStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingFaithStep> createState() => _DatingFaithStepState();
}

class _DatingFaithStepState extends ConsumerState<DatingFaithStep>
    with DatingStepState<DatingFaithStep> {
  String? _faith;
  String? _denomination;
  String? _importance;
  bool _visible = false;
  bool _consent = false;
  bool _consentError = false;

  @override
  void resetAnswers() {
    _faith = null;
    _denomination = null;
    _importance = null;
    _visible = false;
    _consent = false;
    _consentError = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    // Each answer only where the person hasn't changed it (T6 fix 2); a
    // denomination belongs to its faith, so a faith picked early keeps
    // the saved denomination out too.
    if (!isTouched('faith')) {
      _faith = p.faith;
      if (!isTouched('denomination')) _denomination = p.denomination;
    }
    if (!isTouched('importance')) _importance = p.importance;
    if (!isTouched('visible')) _visible = p.faithVisible;
  }

  void _continue(DatingFaith faith, String importance) {
    if (!_consent) {
      setState(() => _consentError = true);
      return;
    }
    // Only a denomination on the faith's own list (fix 1, M-4): a hidden
    // one would be refused, and nothing on screen could clear it.
    final denomination =
        faith.denominations.any((d) => d.code == _denomination)
            ? _denomination
            : null;
    write(
      'd8',
      [faith.code, denomination, importance, _visible],
      (key) => ref
          .read(datingSetupGatewayProvider)
          .saveFaith(
            key,
            faith: faith.code,
            denomination: denomination,
            importance: importance,
            visible: _visible,
          ),
      (w) => widget.nav.next(w.nextStep ?? 'photos'),
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
    final faiths =
        lists?.country(profile?.countryCode)?.faiths ?? const <DatingFaith>[];
    // Only a faith on the country's own list is a choice.
    DatingFaith? chosen;
    for (final f in faiths) {
      if (f.code == _faith) chosen = f;
    }
    final faith = chosen;
    final importance = _importance;
    String name(String key, String code) => datingListName(loc, key) ?? code;
    return DatingStepFrame(
      step: 'faith',
      title: loc.dating_faithTitle,
      hint: loc.dating_optional,
      onBack: widget.nav.back,
      onSkip:
          () => write(
            'd8_skip',
            'skip',
            (key) => ref.read(datingSetupGatewayProvider).clearFaith(key),
            (w) => widget.nav.next(w.nextStep ?? 'photos'),
          ),
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
          DatingChoiceGroup<String>(
            label: loc.dating_faithTitle,
            // The screen title already names it (T6 fix 1, I-2).
            showLabel: false,
            options: [
              for (final f in faiths) (f.code, name(f.nameKey, f.code)),
            ],
            value: faith?.code,
            onChanged:
                (v) => answer(['faith', 'denomination'], () {
                  _faith = v;
                  _denomination = null;
                }),
          ),
          if (faith != null && faith.denominations.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String?>(
              label: loc.dating_denomination,
              options: [
                for (final d in faith.denominations)
                  (d.code, name(d.nameKey, d.code)),
              ],
              value: _denomination,
              onChanged:
                  (v) => answer(['denomination'], () => _denomination = v),
              // Optional, so it can be taken back (T6 fix 1, M-4).
              onCleared:
                  () => answer(['denomination'], () => _denomination = null),
            ),
          ],
          if (faith != null) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String>(
              label: loc.dating_importanceQ,
              options: [
                ('doesnt_matter', loc.dating_importanceNo),
                ('nice_to_share', loc.dating_importanceNice),
                ('must_share', loc.dating_importanceMust),
              ],
              value: _importance,
              onChanged: (v) => answer(['importance'], () => _importance = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_faithShow),
              value: _visible,
              onChanged: (v) => answer(['visible'], () => _visible = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(loc.dating_faithConsent),
              value: _consent,
              onChanged:
                  (v) => setState(() {
                    _consent = v ?? false;
                    if (_consent) _consentError = false;
                  }),
            ),
            if (_consentError)
              FlowErrorLine(
                text: loc.dating_faithConsentError,
                liveRegion: true,
              ),
          ],
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
            online &&
                    profileReady &&
                    lists != null &&
                    faith != null &&
                    importance != null
                ? () => _continue(faith, importance)
                : null,
      ),
    );
  }
}
