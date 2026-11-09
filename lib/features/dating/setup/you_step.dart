// Spec 2 §3.2 D5 (Step 4 of 12; §2.4). Off-country (the Dating country's
// same-gender rule off): the line first, Woman or Man only, Why? (static,
// calls nothing) and Support for you; nothing more can be sent. On-country:
// the full set, a more specific term (own words: letters, spaces, hyphens,
// 30), non-binary pools, pronouns (20), visibility off by default.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/dating_support_sheet.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _ownWords = RegExp(r"^\p{L}[\p{L} \-]{0,29}$", unicode: true);

/// The two identities every country offers (§2.4).
const _plain = {'woman', 'man'};

class DatingYouStep extends ConsumerStatefulWidget {
  const DatingYouStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingYouStep> createState() => _DatingYouStepState();
}

class _DatingYouStepState extends ConsumerState<DatingYouStep>
    with DatingStepState<DatingYouStep> {
  String? _identity;
  String? _specific;
  final _own = TextEditingController();
  final _pronouns = TextEditingController();
  final _pools = <String>{};
  bool _visible = false;
  bool _more = false;
  bool _ownInvalid = false;

  @override
  void dispose() {
    _own.dispose();
    _pronouns.dispose();
    super.dispose();
  }

  @override
  void resetAnswers() {
    _identity = null;
    _specific = null;
    _own.clear();
    _pronouns.clear();
    _pools.clear();
    _visible = false;
    _more = false;
    _ownInvalid = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    // Each answer only where the person hasn't changed it (T6 fix 2).
    if (!isTouched('identity')) _identity = p.identity;
    if (!isTouched('specific')) {
      _specific = p.specific ?? (p.specificText != null ? 'own' : null);
      _own.text = p.specificText ?? '';
      if (_specific != null) _more = true;
    }
    if (!isTouched('pronouns')) _pronouns.text = p.pronouns ?? '';
    if (!isTouched('pools')) {
      _pools
        ..clear()
        ..addAll(p.pools.where(_plain.contains));
    }
    if (!isTouched('visible')) _visible = p.genderVisible;
  }

  void _continue(String identity, bool sameGender, DatingMyProfile? saved) {
    String? specific;
    String? pronouns;
    var pools = <String>[];
    // §2.4, §7.4: off-country nothing but Woman or Man is ever sent, even
    // an answer saved while the switch was on.
    if (sameGender) {
      if (_specific == 'own') {
        final text = _own.text.trim();
        if (!_ownWords.hasMatch(text)) {
          setState(() => _ownInvalid = true);
          return;
        }
        specific = text;
      } else {
        specific = _specific;
      }
      final p = _pronouns.text.trim();
      pronouns = p.isEmpty ? null : p;
      pools = identity == 'non_binary' ? (_pools.toList()..sort()) : const [];
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd5',
      [identity, specific, pronouns, pools, _visible],
      (key) => gateway.saveIdentity(
        key,
        identity: identity,
        specific: specific,
        pronouns: pronouns,
        extraPools: pools,
        visible: _visible,
      ),
      (w) {
        final nav = widget.nav;
        final askAgain = nav.askAgain;
        // Final fix (M-8): after the country switch, who-to-meet must be
        // plain too, so "Choose again" always goes on to D6.
        if (nav.from == 'section' && askAgain != null) return askAgain('meet');
        // Final fix (I-3): where same-gender is off, a changed identity
        // asks who-to-meet again (save_dating_identity clears it).
        moveOnFrom(
          nav,
          w.nextStep ?? 'meet',
          predicted:
              (saved?.seeking.isEmpty ?? true) ||
                      (!sameGender && saved?.identity != identity)
                  ? 'meet'
                  : null,
        );
      },
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
    // Unknown is off: nothing same-gender is offered until the rule is known.
    final sameGender = lists?.country(country)?.sameGender ?? false;
    final theme = Theme.of(context);
    // Off-country a saved non-binary answer is no choice (it can't be sent).
    final identity =
        sameGender || _plain.contains(_identity) ? _identity : null;
    return DatingStepFrame(
      step: 'you',
      title: loc.dating_youTitle,
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
          if (known && !sameGender && country != null) ...[
            Text(
              loc.dating_offCountryLine(datingCountryName(loc, country)),
              style: theme.textTheme.bodyLarge,
            ),
            // Under the line, at its start (as D6's Why?).
            FlowTextLink(
              label: loc.dating_why,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => showDatingWhySheet(context, country: country),
            ),
            FlowTextLink(
              label: loc.dating_supportForYou,
              alignment: AlignmentDirectional.centerStart,
              onPressed:
                  () => showDatingSupportSheet(context, country: country),
            ),
            const SizedBox(height: Spacing.sm),
          ],
          if (!known && !listsRead.hasError && !profileFailed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Spacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (known)
            DatingChoiceGroup<String>(
              label: loc.dating_youTitle,
              // The screen title already asks it (T6 fix 1, I-2).
              showLabel: false,
              options: [
                ('woman', loc.dating_identityWoman),
                ('man', loc.dating_identityMan),
                if (sameGender) ('non_binary', loc.dating_identityNonBinary),
              ],
              value: identity,
              onChanged: (v) => answer(['identity'], () => _identity = v),
            ),
          if (sameGender) ...[
            if (!_more)
              FlowTextLink(
                label: loc.dating_moreSpecific,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => setState(() => _more = true),
              )
            else
              DatingChoiceGroup<String?>(
                label: loc.dating_moreSpecific,
                options: [
                  ('trans_woman', loc.dating_specificTransWoman),
                  ('trans_man', loc.dating_specificTransMan),
                  ('genderfluid', loc.dating_specificGenderfluid),
                  ('genderqueer', loc.dating_specificGenderqueer),
                  ('agender', loc.dating_specificAgender),
                  ('intersex', loc.dating_specificIntersex),
                  ('own', loc.dating_specificOwnWords),
                ],
                value: _specific,
                onChanged:
                    (v) => answer(['specific'], () {
                      _specific = v;
                      _ownInvalid = false;
                    }),
                // Optional, so it can be taken back (T6 fix 1, M-4).
                onCleared:
                    () => answer(['specific'], () {
                      _specific = null;
                      _ownInvalid = false;
                    }),
              ),
            if (_more && _specific == 'own')
              TextField(
                key: const ValueKey('dating_ownWords'),
                controller: _own,
                // Final fix (M-12): a shared phone: the keyboard learns and
                // suggests nothing typed here.
                enableSuggestions: false,
                autocorrect: false,
                enableIMEPersonalizedLearning: false,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: loc.dating_specificOwnWords,
                ),
                onChanged:
                    (_) => answer(['specific'], () => _ownInvalid = false),
              ),
            if (_ownInvalid)
              FlowErrorLine(text: loc.dating_specificInvalid, liveRegion: true),
            if (identity == 'non_binary') ...[
              const SizedBox(height: Spacing.md),
              Text(loc.dating_nbPoolsQ, style: theme.textTheme.titleSmall),
              for (final (pool, label) in [
                ('woman', loc.dating_poolWomen),
                ('man', loc.dating_poolMen),
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(label),
                  value: _pools.contains(pool),
                  onChanged:
                      (v) => answer(
                        ['pools'],
                        () =>
                            v == true ? _pools.add(pool) : _pools.remove(pool),
                      ),
                ),
              Text(loc.dating_nbPoolsHelper, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              key: const ValueKey('dating_pronouns'),
              controller: _pronouns,
              // Final fix (M-12): a shared phone: the keyboard learns and
              // suggests nothing typed here.
              enableSuggestions: false,
              autocorrect: false,
              enableIMEPersonalizedLearning: false,
              maxLength: 20,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r"[\p{L}/ \-]", unicode: true),
                ),
              ],
              decoration: InputDecoration(labelText: loc.dating_pronouns),
              onChanged: (_) => answer(['pronouns'], () {}),
            ),
            Wrap(
              spacing: Spacing.sm,
              children: [
                for (final s in const ['she/her', 'he/him', 'they/them'])
                  ActionChip(
                    label: Text(s),
                    onPressed:
                        () => answer(['pronouns'], () => _pronouns.text = s),
                  ),
              ],
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_genderShow),
            value: _visible,
            onChanged: (v) => answer(['visible'], () => _visible = v),
          ),
          Text(loc.dating_youHelper, style: theme.textTheme.bodySmall),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        // Never over saved answers the screen couldn't read, nor before the
        // country's rule is known (T6 fix 2, N-1; §7.4).
        onPressed:
            online && known && identity != null
                ? () => _continue(identity, sameGender, profile)
                : null,
      ),
    );
  }
}
