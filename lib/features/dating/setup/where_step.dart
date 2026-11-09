// Spec 2 §3.2 D3 (Step 2 of 12): the country (preselected from the SIM,
// the device region or the phone number, the first that is open; never
// hard-coded, R-20), the region (a closed one: the inline notice, Continue
// off, "Tell me when it's open in {region}"), the side where defined, the
// scope, the abroad row (disabled until W5c) and the helper.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingWhereStep extends ConsumerStatefulWidget {
  const DatingWhereStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingWhereStep> createState() => _DatingWhereStepState();
}

class _DatingWhereStepState extends ConsumerState<DatingWhereStep>
    with DatingStepState<DatingWhereStep> {
  String? _country;
  String? _region;
  String? _side;
  String _scope = 'region';
  bool _chosen = false;
  DatingNoticeResult? _notice;

  /// The place [_notice] answers for (T6 fix 1, I-1): shown only there.
  (String, String)? _noticeFor;
  bool _asking = false;

  @override
  void resetAnswers() {
    _country = null;
    _region = null;
    _side = null;
    _scope = 'region';
    _chosen = false;
    _notice = null;
    _noticeFor = null;
    _asking = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    if (p.countryCode == null) return;
    // Fix 2 (N-1): the place is one answer (a region belongs to its
    // country, a side to its region); the scope is its own.
    if (!isTouched('country')) {
      _country = p.countryCode;
      _region = p.regionCode;
      _side = p.sideCode;
      _chosen = true;
    }
    if (!isTouched('scope')) _scope = p.regionScope ?? 'region';
    if (_scope == 'side' && _side == null) _scope = 'region';
  }

  String? _preselect(DatingSetupLists lists) {
    final device = ref.watch(deviceCountryProvider).valueOrNull;
    for (final c in [device?.sim, device?.region, lists.phoneCountry]) {
      if (c != null && lists.country(c) != null) return c;
    }
    return null;
  }

  String _regionName(AppLocalizations loc, DatingRegion r) =>
      datingListName(loc, r.nameKey) ?? r.code;

  Future<void> _pickCountry(
    AppLocalizations loc,
    DatingSetupLists lists,
    String? current,
  ) async {
    const notListed = '__not_listed__';
    final account = ref.read(datingAccountProvider);
    final chosen = await showDatingPicker<String>(
      context,
      title: loc.dating_countryLabel,
      selected: current,
      items: [
        for (final c in lists.countries)
          (c.code, datingCountryName(loc, c.code)),
        (notListed, loc.dating_countryNotListed),
      ],
    );
    // D8: a pick made for the last account never lands on the next.
    if (chosen == null ||
        !mounted ||
        ref.read(datingAccountProvider) != account) {
      return;
    }
    if (chosen == notListed) {
      final device = ref.read(deviceCountryProvider).valueOrNull;
      context.push(
        DatingPaths.notOpenFor(
          country: device?.sim ?? device?.region ?? lists.phoneCountry,
        ),
      );
      return;
    }
    answer(['country', 'scope'], () {
      _chosen = true;
      if (chosen != _country) {
        _country = chosen;
        _region = null;
        _side = null;
        _scope = 'region';
        _notice = null;
      }
    });
  }

  Future<void> _pickRegion(
    AppLocalizations loc,
    DatingCountryLists country,
  ) async {
    final regions = [...country.regions]
      ..sort((a, b) => _regionName(loc, a).compareTo(_regionName(loc, b)));
    final account = ref.read(datingAccountProvider);
    final chosen = await showDatingPicker<String>(
      context,
      title: loc.dating_regionLabel,
      selected: _region,
      items: [for (final r in regions) (r.code, _regionName(loc, r))],
    );
    if (chosen == null ||
        !mounted ||
        ref.read(datingAccountProvider) != account) {
      return;
    }
    answer(['country'], () {
      // The region is picked in the country on screen (maybe preselected).
      _chosen = true;
      _country = country.code;
      _region = chosen;
      _side = null;
      if (_scope == 'side') _scope = 'region';
      _notice = null;
    });
  }

  /// I-1: as §3.10's "Tell me": one request at a time, every answer said
  /// calmly, and nothing of one account's answer shown to the next (D8).
  Future<void> _tellMe(String country, String region) async {
    if (_asking) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _asking = true;
      _notice = null;
      _noticeFor = null;
    });
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: region);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    if (result == DatingNoticeResult.alreadyOpen) {
      // The region opened meanwhile: read the lists again, so it shows as
      // open and Continue can go on.
      ref.invalidate(datingSetupListsProvider(account));
    }
    setState(() {
      _asking = false;
      _notice = result;
      _noticeFor = (country, region);
    });
  }

  Widget? _noticeLine(AppLocalizations loc, ThemeData theme) {
    Widget calm(String text) => Semantics(
      liveRegion: true,
      child: Text(text, style: theme.textTheme.bodyMedium),
    );
    return switch (_notice) {
      DatingNoticeResult.busy => calm(loc.dating_busy),
      DatingNoticeResult.rateLimited => calm(loc.dating_errorRateLimited),
      DatingNoticeResult.notEligible => calm(loc.dating_noticeNotEligible),
      DatingNoticeResult.failed || DatingNoticeResult.invalid => FlowErrorLine(
        text: loc.dating_errorGeneric,
        liveRegion: true,
      ),
      _ => null,
    };
  }

  void _continue(String country, String region, String? saved) {
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd3',
      [country, region, _side, _scope],
      (key) => gateway.saveLocation(
        key,
        country: country,
        region: region,
        side: _side,
        scope: _scope,
      ),
      // Final fix (I-3): a new Dating country asks gender and
      // who-to-meet again (save_dating_location clears both).
      (w) => moveOnFrom(
        widget.nav,
        w.nextStep ?? 'privacy',
        predicted: saved != null && saved != country ? 'you' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final saved = watchProfile()?.countryCode;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final account = ref.watch(datingAccountProvider);
    final listsRead = ref.watch(datingSetupListsProvider(account));
    // A failed read shows nothing of an old value (carry B, D8).
    final lists = listsRead.hasError ? null : listsRead.valueOrNull;
    final loadFailed = listsRead.hasError || profileFailed;
    final countryCode =
        _chosen ? _country : (lists == null ? null : _preselect(lists));
    final country = lists?.country(countryCode);
    final region = country?.region(_region);
    final closed = region != null && !region.open;
    final theme = Theme.of(context);
    final here =
        country != null &&
        region != null &&
        _noticeFor == (country.code, region.code);
    final noticeLine = _noticeLine(loc, theme);
    Widget row(String label, String? value, VoidCallback? onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value ?? loc.dating_choose),
      trailing: const Icon(Icons.expand_more),
      onTap: onTap,
    );
    return DatingStepFrame(
      step: 'where',
      title: loc.dating_whereTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loadFailed)
            DatingLoadError(
              busy: listsRead.isLoading || profileRetrying,
              onRetry: () {
                if (listsRead.hasError) {
                  ref.invalidate(datingSetupListsProvider(account));
                }
                if (profileFailed) retryProfile();
              },
            ),
          row(
            loc.dating_countryLabel,
            countryCode == null ? null : datingCountryName(loc, countryCode),
            lists == null ? null : () => _pickCountry(loc, lists, countryCode),
          ),
          if (country != null)
            row(
              loc.dating_regionLabel,
              region == null ? null : _regionName(loc, region),
              () => _pickRegion(loc, country),
            ),
          if (closed && country != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                loc.dating_regionClosed(
                  datingRegionList(loc, country.code, [
                    for (final r in country.regions)
                      if (r.open) r.code,
                  ]),
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (here && _notice == DatingNoticeResult.saved)
              Text(loc.dating_tellMeDone, style: theme.textTheme.bodyMedium)
            else ...[
              FlowSecondaryButton(
                label: loc.dating_tellMeRegion(_regionName(loc, region)),
                busy: _asking,
                onPressed:
                    online ? () => _tellMe(country.code, region.code) : null,
              ),
              if (here && noticeLine != null) ...[
                const SizedBox(height: Spacing.sm),
                noticeLine,
              ],
            ],
          ],
          if (region != null && region.open && region.sides.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String?>(
              label: loc.dating_sideLabel(_regionName(loc, region)),
              options: [
                for (final s in region.sides)
                  (s.code, datingListName(loc, s.nameKey) ?? s.code),
                (null, loc.dating_sideEither),
              ],
              value: _side,
              onChanged:
                  (v) => answer(['country'], () {
                    _side = v;
                    if (v == null && _scope == 'side') _scope = 'region';
                  }),
            ),
          ],
          if (region != null && region.open) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String>(
              label: loc.dating_scopeQ,
              options: [
                if (_side != null) ('side', loc.dating_scopeSide),
                ('region', loc.dating_scopeRegion),
                (
                  'country',
                  loc.dating_scopeCountry(
                    datingCountryName(loc, country!.code),
                  ),
                ),
              ],
              value: _scope,
              onChanged: (v) => answer(['scope'], () => _scope = v),
            ),
          ],
          const SizedBox(height: Spacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: false,
            title: Text(loc.dating_abroadRow),
            subtitle: Text(loc.dating_abroadDisabled),
          ),
          Text(loc.dating_whereHelper, style: theme.textTheme.bodySmall),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            // M-3: never over saved answers the screen couldn't read.
            online &&
                    profileReady &&
                    countryCode != null &&
                    region != null &&
                    region.open
                ? () => _continue(countryCode, region.code, saved)
                : null,
      ),
    );
  }
}
