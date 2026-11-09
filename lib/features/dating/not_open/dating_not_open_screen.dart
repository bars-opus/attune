// Spec 2 W3a (§3.10; R-36): "Dating isn't open in {country} yet", or its
// region variant. No animation, no waitlist number; the open list is
// built from get_dating_availability. A country chosen here stays in this
// screen's memory only (D20). "Use Attune just for me" only on the Dating
// path.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingNotOpenScreen extends ConsumerStatefulWidget {
  const DatingNotOpenScreen({super.key, this.country, this.region});

  final String? country;
  final String? region;

  @override
  ConsumerState<DatingNotOpenScreen> createState() =>
      _DatingNotOpenScreenState();
}

class _DatingNotOpenScreenState extends ConsumerState<DatingNotOpenScreen> {
  String? _country;
  bool _busy = false;
  bool? _requested;
  DatingNoticeResult? _result;

  static String? _iso(String? code) {
    final upper = code?.trim().toUpperCase();
    return upper != null && RegExp(r'^[A-Z]{2}$').hasMatch(upper)
        ? upper
        : null;
  }

  @override
  void initState() {
    super.initState();
    _country = _iso(widget.country);
    // Final fix (M-2, D8): another account on the phone starts from the
    // link alone: no country picked, request or answer of the last one.
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _country = _iso(widget.country);
        _busy = false;
        _requested = null;
        _result = null;
      });
    });
  }

  /// Fix round 1 (Minor 3): a deep link's region is a code or nothing; any
  /// other text is never put on screen.
  String? get _region {
    final code = widget.region?.trim().toUpperCase();
    return _country != null &&
            code != null &&
            RegExp(r'^[A-Z0-9]{1,3}$').hasMatch(code)
        ? code
        : null;
  }

  /// Whether [region] of [country] is open in the config (R-5).
  static bool _regionOpen(
    DatingAvailability open,
    String country,
    String region,
  ) {
    for (final c in open.countries) {
      if (c.code != country) continue;
      final keys = c.openRegionKeys;
      return keys == null ||
          keys.contains(
            'dating_region_${country.toLowerCase()}_${region.toLowerCase()}',
          );
    }
    return false;
  }

  Future<void> _ask() async {
    final country = _country;
    if (_busy || country == null) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: _region);
    // M-2: an answer for the last account never lands on the next.
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // Fix round 1 (I-1, Minor 1): the home changed (or was stale): read
    // it again. Open already: nothing to wait for, so back to Me.
    if (result == DatingNoticeResult.saved ||
        result == DatingNoticeResult.alreadyOpen) {
      ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));
    }
    if (result == DatingNoticeResult.alreadyOpen) {
      context.go(homeLocation(tab: AppTab.me));
      return;
    }
    setState(() {
      _busy = false;
      _result = result;
      if (result == DatingNoticeResult.saved) _requested = true;
    });
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await ref.read(datingHomeGatewayProvider).cancelNotice();
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      if (result == DatingNoticeResult.saved) {
        _requested = false;
      } else {
        _result = result;
      }
    });
  }

  Future<void> _pick() async {
    await BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      padding: 0,
      widget: PhoneCountryPickerSheet(
        selectedCountry: PhoneCountries.defaultCountry,
        onCountrySelected: (country) {
          if (mounted) setState(() => _country = country.isoCode);
        },
      ),
    );
  }

  /// Fix round 1 (Minor 2): as the section's "Not ready?": an open shared
  /// space shows its sheet; only a switch that went through opens Me.
  Future<void> _justMe() async {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return;
    final shown = ref.read(homeStateProvider(userId));
    final outcome = await switchPath(
      context,
      ref,
      to: AppPath.justMe,
      oneTap: true,
      home: shown,
    );
    if (!mounted) return;
    if (outcome == PathChoiceOutcome.relationshipOpen) {
      await showSharedSpaceSheetAfterRefusal(context, shown);
    } else if (outcome == PathChoiceOutcome.done) {
      context.go(homeLocation(tab: AppTab.me));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final known = ref.watch(datingAvailabilityProvider).valueOrNull;
    final open = known ?? const DatingAvailability();
    final home =
        ref
            .watch(datingHomeProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final userId = ref.watch(homeAuthProvider).currentUser?.id;
    final onDating =
        userId != null &&
        ref.watch(homeStateProvider(userId)).path == AppPath.dating;
    final country = _country;
    final region = _region;
    final requested =
        _requested ??
        (home != null &&
            home.country == country &&
            home.region == region &&
            home.notice.requested);
    final regional = region != null && country != null;
    // Fix round 1 (I-1, R-5): is this place closed? The home answers for
    // its own place (notify.available: Dating off where the country is
    // open is not "closed"); any other place, the open list. Unknown
    // yet: neither, so nothing is offered until it is known.
    final homeHere =
        home != null &&
        home.country == country &&
        (regional
            ? home.state == DatingHomeState.regionClosed &&
                home.region == region
            : home.state == DatingHomeState.featureUnavailable ||
                home.state == DatingHomeState.countryClosed);
    final bool? closed =
        country == null
            ? null
            : homeHere
            ? home.notice.available
            : known == null
            ? null
            : regional
            ? !_regionOpen(known, country, region)
            : !known.isOpen(country);
    // An open place never reads "isn't open in {country}" (I-1).
    final placeOpen = closed == false;
    final title =
        country == null || placeOpen
            ? loc.flow_slotClosedTitle
            : regional
            ? loc.dating_notOpenRegionTitle(
              datingOpenRegionNames(loc, open, country),
            )
            : loc.dating_notOpenTitle(datingCountryName(loc, country));
    return FlowFrame(
      title: title,
      onBack:
          () =>
              context.canPop()
                  ? context.pop()
                  : context.go(homeLocation(tab: AppTab.me)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) ...[
            Text(loc.dating_offline, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Spacing.md),
          ],
          Text(
            placeOpen
                ? loc.flow_slotClosedBody
                : regional
                ? loc.dating_notOpenRegionBody
                : loc.dating_notOpenBody(datingOpenList(loc, open)),
            style: theme.textTheme.bodyLarge,
          ),
          if (requested) ...[
            const SizedBox(height: Spacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                loc.dating_tellMeDone,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FlowTextLink(
              label: loc.dating_settingsTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.settings),
            ),
            if (online)
              FlowTextLink(
                label: loc.dating_tellMeOff,
                alignment: AlignmentDirectional.centerStart,
                onPressed: _cancel,
              ),
          ],
          if (_result == DatingNoticeResult.busy) ...[
            const SizedBox(height: Spacing.sm),
            Text(loc.dating_busy, style: theme.textTheme.bodyMedium),
          ],
          // Carry B (R-45, T3 M-5): the cap and the adult check, calmly.
          if (_result == DatingNoticeResult.rateLimited ||
              _result == DatingNoticeResult.notEligible) ...[
            const SizedBox(height: Spacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _result == DatingNoticeResult.rateLimited
                    ? loc.dating_errorRateLimited
                    : loc.dating_noticeNotEligible,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
          if (_result == DatingNoticeResult.failed ||
              _result == DatingNoticeResult.invalid) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          ],
        ],
      ),
      actions: [
        if (country == null)
          FlowPrimaryButton(label: loc.flow_slotChooseCountry, onPressed: _pick)
        else if (!requested && closed == true)
          FlowPrimaryButton(
            label:
                regional
                    ? loc.dating_tellMeRegion(
                      datingRegionName(loc, country, region),
                    )
                    : loc.dating_tellMe,
            busy: _busy,
            onPressed: online ? _ask : null,
          ),
        if (onDating)
          FlowSecondaryButton(label: loc.dating_justForMe, onPressed: _justMe),
      ],
    );
  }
}
