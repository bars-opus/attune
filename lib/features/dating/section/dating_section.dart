// Spec 2 W3a (§3.1, §3.15; carries 1, 3, 8, 9, 13): the Dating section in
// Me, driven by get_dating_home() alone. Every state the server names has
// its card; any other reads as unavailable (Task 1's model). A 200 ms
// cross-fade between states (none with reduce motion); one semantic region
// "Dating"; a failed or offline read says so (nothing is cached). Nothing
// here is kept on the phone (D20); taps belong to the account that made
// them (D8).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart'
    show datingStepLocation;
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingSection extends ConsumerStatefulWidget {
  const DatingSection({super.key});

  @override
  ConsumerState<DatingSection> createState() => _DatingSectionState();
}

class _DatingSectionState extends ConsumerState<DatingSection>
    with WidgetsBindingObserver {
  final _keys = DatingActionKeys();
  bool _busy = false;
  DatingLifecycleError? _error;
  DatingNoticeResult? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _busy = false;
        _error = null;
        _notice = null;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() =>
      ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));

  Future<void> _resume() async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(datingLifecycleGatewayProvider)
        .resume(_keys.keyFor('resume', account));
    // Carry A (T1 I-1): a final answer drops the key, so the next Resume
    // is a new request; busy or failed keeps it for the retry.
    _keys.settle('resume', error: result.error);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    final error = result.error;
    setState(() {
      _busy = false;
      // Already resumed elsewhere: just read the home again.
      _error = error == DatingLifecycleError.notPaused ? null : error;
    });
    if (result.ok || error == DatingLifecycleError.notPaused) _refresh();
  }

  Future<void> _tellMe(String country, String? region) async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: region);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _notice = result;
    });
    // Fix round 1 (Minor 1): a saved request changes the home too (the
    // notice and has_data, so the settings link), as already_open does.
    if (result == DatingNoticeResult.saved ||
        result == DatingNoticeResult.alreadyOpen) {
      _refresh();
    }
  }

  /// Spec 1's one-tap "Not ready?" (as the slot had it).
  Future<void> _notReady() async {
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
    if (outcome == PathChoiceOutcome.relationshipOpen && mounted) {
      await showSharedSpaceSheetAfterRefusal(context, shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    // One entry per account (D8), so a value here is this account's; a
    // failed refresh never shows the last state (nothing is cached).
    final data = home.hasError ? null : home.valueOrNull;
    final Object key;
    final Widget child;
    if (data != null) {
      key = data.state;
      child = _card(context, loc, data, online);
    } else if (home.hasError) {
      key = 'error';
      child = _SectionCard(
        title: loc.flow_slotDatingTitle,
        children: [
          if (!online)
            _Calm(loc.dating_offline)
          else
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          FlowSecondaryButton(
            label: loc.dating_retry,
            busy: home.isLoading,
            onPressed: _refresh,
          ),
          // T12 fix 1 (M-3): while the home can't be read, Leave and Clear
          // stay one tap away (settings offers both on an unread home).
          FlowTextLink(
            label: loc.dating_settingsTitle,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => context.push(DatingPaths.settings),
          ),
        ],
      );
    } else {
      key = 'loading';
      child = const SizedBox(height: 96);
    }
    return Semantics(
      container: true,
      label: loc.flow_slotDatingTitle,
      // A new account gets a new switcher (D8, I-8): the last account's
      // card never stays in the tree while it would fade out.
      child: KeyedSubtree(
        key: ValueKey(account),
        child: AnimatedSwitcher(
          duration:
              reduceMotionOf(context)
                  // Fix round 1 (Minor 4): reduce motion fades at 150 ms.
                  ? kReducedMotionFade
                  : const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(key), child: child),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations loc,
    DatingHome h,
    bool online,
  ) {
    final country = h.country;
    // C-2: whenever there is Dating data to leave or clear, in every state,
    // Dating settings (and with it Leave and Clear) is one tap away.
    final settings =
        h.hasData || h.hasProfile || h.notice.requested
            ? FlowTextLink(
              label: loc.dating_settingsTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.settings),
            )
            : null;
    final notReady = FlowTextLink(
      label: loc.flow_slotNotReady,
      alignment: AlignmentDirectional.centerStart,
      onPressed: _notReady,
    );
    switch (h.state) {
      case DatingHomeState.featureUnavailable:
      case DatingHomeState.countryClosed:
        return _SectionCard(
          title:
              country == null
                  ? loc.flow_slotClosedTitle
                  : loc.dating_sectionNotOpen(datingCountryName(loc, country)),
          onTap: () => context.push(DatingPaths.notOpenFor(country: country)),
          children: [
            ..._notice_(loc, h, online, loc.dating_tellMe, null),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.regionClosed:
        final c = country ?? '';
        return _SectionCard(
          title: loc.dating_sectionRegionOpenOnly(
            datingRegionList(loc, c, h.openRegions),
          ),
          onTap:
              () => context.push(
                DatingPaths.notOpenFor(country: country, region: h.region),
              ),
          children: [
            ..._notice_(
              loc,
              h,
              online,
              loc.dating_tellMeRegion(datingRegionName(loc, c, h.region ?? '')),
              h.region,
            ),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.gentleWait:
        final opens = h.opensAt;
        return _SectionCard(
          title:
              opens == null
                  ? loc.flow_slotGentleWaitNoDate
                  : loc.flow_slotGentleWait(
                    MyDateFormat.toDate(opens.toLocal()),
                  ),
          onTap: () => context.push(DatingPaths.step('wait')),
          children: [
            FlowTextLink(
              label: loc.dating_gentleWaitTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.step('wait')),
            ),
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.notStarted:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionNotStarted],
          children: [
            FlowPrimaryButton(
              label: loc.flow_slotSetUp,
              onPressed: () => context.push(DatingPaths.step('how')),
            ),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.setupInProgress:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          children: [
            FlowSecondaryButton(
              label: loc.dating_sectionFinish,
              onPressed:
                  () => context.push(DatingPaths.step(h.nextStep ?? 'how')),
            ),
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.coolOff:
        final at = h.firstDropAt?.toLocal();
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [
            if (at != null)
              loc.dating_sectionFirstDrop(
                MyDateFormat.toDate(at),
                MyDateFormat.toTime(at),
              ),
          ],
          children: [if (settings != null) settings],
        );
      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionActive],
          children: [if (settings != null) settings],
        );
      case DatingHomeState.paused:
        return _paused(context, loc, h, online, settings);
      case DatingHomeState.reverifyDevice:
        return _plain(loc, loc.dating_sectionReverify, settings);
      case DatingHomeState.restricted:
        return _plain(loc, loc.dating_sectionRestricted, settings);
      case DatingHomeState.hold:
        return _plain(loc, loc.dating_sectionHold, settings);
      case DatingHomeState.ageReview:
        return _plain(loc, loc.dating_sectionAgeReview, settings);
      case DatingHomeState.unavailable:
        return _plain(loc, loc.dating_sectionUnavailable, settings);
    }
  }

  Widget _plain(AppLocalizations loc, String line, Widget? settings) =>
      _SectionCard(
        title: loc.flow_slotDatingTitle,
        lines: [line],
        children: [if (settings != null) settings],
      );

  List<Widget> _notice_(
    AppLocalizations loc,
    DatingHome h,
    bool online,
    String label,
    String? region,
  ) {
    final country = h.country;
    return [
      if (h.notice.requested || _notice == DatingNoticeResult.saved)
        _Calm(loc.dating_tellMeDone)
      else if (h.notice.available && country != null)
        FlowSecondaryButton(
          label: label,
          busy: _busy,
          onPressed: online ? () => _tellMe(country, region) : null,
        ),
      if (_notice == DatingNoticeResult.busy) _Calm(loc.dating_busy),
      // Carry B (R-45, T3 M-5): the cap and the adult check, calmly.
      if (_notice == DatingNoticeResult.rateLimited)
        _Calm(loc.dating_errorRateLimited),
      if (_notice == DatingNoticeResult.notEligible)
        _Calm(loc.dating_noticeNotEligible),
      if (_notice == DatingNoticeResult.failed ||
          _notice == DatingNoticeResult.invalid)
        FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
    ];
  }

  Widget _paused(
    BuildContext context,
    AppLocalizations loc,
    DatingHome h,
    bool online,
    Widget? settings,
  ) {
    final reason = h.pauseReason;
    // Every reason has a safe card (carry 9); Resume only where resume can
    // work (the shared space, a parked number or travel keep it paused):
    // DatingHome.resumeOffered, the rule Dating settings uses too (T12 B).
    // Fix round 1 (I-2): the server says whether a shared space holds the
    // pause now. While one does, nothing resumes; a relationship pause
    // read after the space ended is a plain pause that can resume.
    final spaceOpen =
        reason == DatingPauseReason.relationship && h.canResume != true;
    final canResume = h.resumeOffered;
    final line = switch (reason) {
      DatingPauseReason.relationship =>
        spaceOpen
            ? loc.dating_sectionPausedRelationship
            : loc.dating_sectionPaused,
      DatingPauseReason.sameGenderSwitch => loc.dating_sectionSameGenderNote(
        datingCountryName(loc, h.country ?? ''),
      ),
      DatingPauseReason.away => loc.dating_sectionAway,
      _ => loc.dating_sectionPaused,
    };
    return _SectionCard(
      title: loc.flow_slotDatingTitle,
      lines: [line],
      children: [
        if (reason == DatingPauseReason.sameGenderSwitch) ...[
          FlowTextLink(
            label: loc.dating_why,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => showDatingWhySheet(context, country: h.country ?? ''),
          ),
          FlowSecondaryButton(
            label: loc.dating_chooseAgain,
            // Final fix (M-8): D5 then D6, then back here (read again).
            onPressed:
                () => context.push(datingStepLocation('you?from=section')!),
          ),
        ],
        if (canResume)
          FlowPrimaryButton(
            label: loc.dating_resume,
            busy: _busy,
            onPressed: online ? _resume : null,
          ),
        if (_error != null) ..._errorRows(context, loc, _error!),
        if (settings != null) settings,
      ],
    );
  }

  List<Widget> _errorRows(
    BuildContext context,
    AppLocalizations loc,
    DatingLifecycleError error,
  ) {
    Widget link(String label, String to) => FlowTextLink(
      label: label,
      alignment: AlignmentDirectional.centerStart,
      onPressed: () => context.push(to),
    );
    return switch (error) {
      DatingLifecycleError.pathNotDating => [
        FlowErrorLine(text: loc.dating_errorPathNotDating, liveRegion: true),
        link(loc.dating_openHowYouUse, RouteNames.howYouUseAttune),
      ],
      DatingLifecycleError.consentRequired => [
        FlowErrorLine(text: loc.dating_errorConsent, liveRegion: true),
        link(loc.dating_sectionFinish, DatingPaths.step('privacy')),
      ],
      DatingLifecycleError.profileIncomplete ||
      DatingLifecycleError.activationRequired ||
      DatingLifecycleError.enrollmentIncomplete => [
        FlowErrorLine(text: loc.dating_errorIncomplete, liveRegion: true),
        link(loc.dating_sectionFinish, DatingPaths.step('how')),
      ],
      DatingLifecycleError.resumeGatesNotMet ||
      DatingLifecycleError.notEligible => [
        FlowErrorLine(text: loc.dating_errorResumeGates, liveRegion: true),
      ],
      DatingLifecycleError.reverifyDevice => [
        _Calm(loc.dating_sectionReverify),
      ],
      DatingLifecycleError.busy => [_Calm(loc.dating_busy)],
      DatingLifecycleError.rateLimited => [
        FlowErrorLine(text: loc.dating_errorRateLimited, liveRegion: true),
      ],
      _ => [FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true)],
    };
  }
}

/// A calm line, read out when it appears (never the error colour).
class _Calm extends StatelessWidget {
  const _Calm(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.lines = const [],
    this.children = const [],
    this.onTap,
  });

  final String title;
  final List<String> lines;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                for (final child in children) ...[
                  const SizedBox(height: Spacing.sm),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
