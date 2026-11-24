// Spec 2 W9 (§3.9 steps 1-4, §3.14 /dating/link/:matchId, §3.15; D8):
// "Become a couple on Attune". The private "What are we agreeing to?"
// page, read in full before its buttons: for the asker [Ask {Name}]
// [Not now] with "Keep our first messages"; for the other side, after
// "{Name} would like to become a couple on Attune.", [Yes, let's]
// [Not right now] with their own "Keep our first messages". After the
// second Yes, "You decided together." with the one settle (at most 600
// ms, once; a fade under reduce motion), then the Relationship home. The
// asker sees the same moment once (here, in the chat, or on the
// Relationship home's card). Nothing else moves. Offline nothing is
// sent ("You're offline. Nothing has changed yet." for the second Yes);
// busy and failures are calm lines; another account on the phone sees
// nothing of the last one's; nothing is done once quick exit or sign-out
// has run (W8a).
import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/link/dating_link.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart'
    show datingSheetRefused;
import 'package:attune/features/dating/routes/dating_root_back.dart';
import 'package:attune/features/dating/routes/dating_routes.dart'
    show DatingPaths;
import 'package:attune/features/dating/section/dating_calm_line.dart';
import 'package:attune/features/dating/verify/dating_reverify_line.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart'
    show homeStateProvider;
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_screen.dart' show relationshipModeResyncSignal;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.15: the one settle on "You decided together.", at most 600 ms.
const kDatingLinkSettle = Duration(milliseconds: 600);

/// [name], or "this person" when the server has none.
String datingLinkName(AppLocalizations loc, String name) =>
    name.isEmpty ? loc.dating_cardThisPerson : name;

/// Fix round 1 (I-1): the longest Continue waits for "seen" to land.
const kDatingLinkSeenWait = Duration(seconds: 3);

/// After the couple linked: Spec 1's home reads the new path, then the
/// Relationship home.
Future<void> datingGoToCouple(BuildContext context, WidgetRef ref) async {
  final account = ref.read(datingAccountProvider);
  if (account != null) {
    unawaited(ref.read(homeStateProvider(account).notifier).refresh());
  }
  relationshipModeResyncSignal.value++;
  if (context.mounted) context.go(homeLocation(tab: AppTab.chat));
}

/// Fix round 1 (I-1, M-3): "You decided together." answered (Continue, or
/// back from it). With [seen] (the moment was still to show for this
/// side), it is marked seen first, waiting at most [kDatingLinkSeenWait]
/// (a failed mark goes on: showing it again later is the safe side), so
/// the Relationship home's card never shows it again straight after; the
/// card's offer is read anew; then the Relationship home. The router and
/// the container are taken first, so a back that already left the page
/// still lands there. Nothing more once quick exit or sign-out has run, or
/// another account signed in (W8a, D8).
Future<void> datingLinkDone(BuildContext context, {required bool seen}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final router = GoRouter.of(context);
  final account = container.read(datingAccountProvider);
  if (account == null || datingSheetRefused) return;
  if (seen) {
    await container
        .read(datingLinkGatewayProvider)
        .dismiss(DatingPostLinkOffer.linked)
        .timeout(kDatingLinkSeenWait, onTimeout: () => false)
        .catchError((Object _) => false);
  }
  if (datingSheetRefused || container.read(datingAccountProvider) != account) {
    return;
  }
  container.invalidate(datingPostLinkOfferProvider(account));
  unawaited(container.read(homeStateProvider(account).notifier).refresh());
  relationshipModeResyncSignal.value++;
  router.go(homeLocation(tab: AppTab.chat));
}

/// "You decided together.": one settle, at most 600 ms, once (a fade under
/// reduce motion), announced; [onContinue] goes on (Continue is busy, and
/// taps nothing more, until it has finished).
class DatingLinkMoment extends StatefulWidget {
  const DatingLinkMoment({super.key, required this.onContinue, this.body});

  final FutureOr<void> Function()? onContinue;
  final String? body;

  @override
  State<DatingLinkMoment> createState() => _DatingLinkMomentState();
}

class _DatingLinkMomentState extends State<DatingLinkMoment>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: kDatingLinkSettle,
  );
  bool _started = false;
  bool _going = false;

  Future<void> _continue() async {
    final go = widget.onContinue;
    if (go == null || _going) return;
    setState(() => _going = true);
    try {
      await go();
    } finally {
      if (mounted) setState(() => _going = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (reduceMotionOf(context)) {
      _settle.duration = const Duration(milliseconds: 150);
    }
    _settle.forward();
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final still = reduceMotionOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: _settle,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_settle.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, still ? 0 : 12 * (1 - t)),
                child: child,
              ),
            );
          },
          child: Semantics(
            liveRegion: true,
            header: true,
            child: Text(
              loc.dating_linkDecided,
              key: const ValueKey('dating_link_decided'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (widget.body != null) ...[
          const SizedBox(height: Spacing.sm),
          Text(
            widget.body!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        FlowPrimaryButton(
          key: const ValueKey('dating_link_continue'),
          label: loc.flow_continue,
          busy: _going,
          onPressed: widget.onContinue == null ? null : _continue,
        ),
      ],
    );
  }
}

/// §3.14 /dating/link/:matchId.
class DatingLinkScreen extends ConsumerStatefulWidget {
  const DatingLinkScreen({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<DatingLinkScreen> createState() => _DatingLinkScreenState();
}

enum _LinkBusy { ask, yes, no, back }

class _DatingLinkScreenState extends ConsumerState<DatingLinkScreen> {
  final _keys = DatingActionKeys();
  DatingLinkPage? _page;
  String? _account;
  bool _keep = false;
  _LinkBusy? _busy;
  String? _error;

  /// The second Yes landed here: the moment, then the Relationship home.
  bool _decided = false;

  /// A Yes was sent from this page (Ruling 2: a re-read that finds the
  /// couple linked is this side's own moment).
  bool _sentYes = false;

  /// Fix round 1 (M-3): the moment is answered (Continue or back) once.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _account = ref.read(datingAccountProvider);
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      // D8: another account sees nothing of the last one's.
      setState(() {
        _account = next;
        _page = null;
        _keep = false;
        _busy = null;
        _error = null;
        _decided = false;
        _sentYes = false;
        _leaving = false;
      });
      _keys.clear();
      unawaited(_read());
    });
    unawaited(_read());
  }

  Future<void> _read() async {
    final account = _account;
    if (account == null) return;
    final page = await ref.read(datingLinkGatewayProvider).page(widget.matchId);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // A re-read that could not answer keeps what is shown (the action's own
    // line says why), so a busy server never takes the buttons away.
    if (_page != null &&
        !page.ok &&
        (page.reason == 'busy' || page.reason == 'failed')) {
      return;
    }
    setState(() => _page = page);
  }

  /// Back to the chat (as the only page, the chat itself).
  void _back() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(DatingPaths.chat(widget.matchId));
    }
  }

  Future<void> _run(
    _LinkBusy what,
    Future<DatingLinkAnswer> Function() call,
  ) async {
    // W8a: nothing is done under quick exit's decoy.
    if (_busy != null || datingSheetRefused) return;
    final account = _account;
    if (account == null) return;
    setState(() {
      _busy = what;
      _error = null;
      if (what == _LinkBusy.yes) _sentYes = true;
    });
    final r = await call();
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    // Fix round 1 (M-6): a final answer lets the key go (busy or failed
    // keep it: the retry is the same request).
    if (what == _LinkBusy.ask) _keys.settle('ask', reason: r.reason);
    if (what == _LinkBusy.yes) _keys.settle('yes', reason: r.reason);
    setState(() {
      _busy = null;
      _error = r.ok ? null : r.reason;
    });
    if (!r.ok) {
      // A refusal that means the link moved on: read it again. After a
      // sent Yes, busy or failed may hide a link that landed (the second
      // Yes is idempotent by the request's state, never by its key): read
      // it again too, and the moment shows if it did.
      if (const {
            'asked',
            'asked_you',
            'not_yet',
            'not_ready',
            'request_unavailable',
            'closed',
            'match_unavailable',
            'linked',
          }.contains(r.reason) ||
          (what == _LinkBusy.yes &&
              (r.reason == 'busy' || r.reason == 'failed'))) {
        unawaited(_read());
      }
      return;
    }
    switch (what) {
      case _LinkBusy.yes:
        setState(() => _decided = true);
      case _LinkBusy.ask:
        unawaited(_read());
      case _LinkBusy.no || _LinkBusy.back:
        _back();
    }
  }

  Widget _agreeing(AppLocalizations loc, String name, {required bool asker}) {
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final requestId = _page?.link?.requestId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!asker) ...[
          Text(
            loc.dating_linkAskedYou(name),
            key: const ValueKey('dating_link_asked_you'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
        Semantics(
          header: true,
          child: Text(
            loc.dating_linkAgreeingTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          loc.dating_linkAgreeingBody,
          key: const ValueKey('dating_link_body'),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: Spacing.md),
        MergeSemantics(
          child: CheckboxListTile(
            key: const ValueKey('dating_link_keep'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _keep,
            onChanged:
                _busy == null
                    ? (v) => setState(() => _keep = v ?? false)
                    : null,
            title: Text(loc.dating_linkKeep(name)),
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (!online)
          DatingCalmLine(asker ? loc.dating_offline : loc.dating_linkOffline),
        if (_error == 'busy') DatingCalmLine(loc.dating_busy),
        if (_error == 'reverify_device') const DatingReverifyLine(),
        if (_error == 'match_unavailable' ||
            _error == 'request_unavailable' ||
            _error == 'closed')
          DatingCalmLine(loc.dating_cardGone),
        if (_error == 'unavailable') DatingCalmLine(loc.dating_linkUnavailable),
        if (_error == 'failed' || _error == 'invalid')
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        if (asker) ...[
          FlowPrimaryButton(
            key: const ValueKey('dating_link_ask'),
            label: loc.dating_linkAsk(name),
            busy: _busy == _LinkBusy.ask,
            onPressed:
                online && _busy == null
                    ? () => _run(
                      _LinkBusy.ask,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .ask(
                            _keys.keyFor('ask', [
                              _account,
                              widget.matchId,
                              _keep,
                            ]),
                            widget.matchId,
                            keep: _keep,
                          ),
                    )
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_link_not_now'),
            label: loc.dating_linkNotNow,
            onPressed: _busy == null ? _back : null,
          ),
        ] else ...[
          FlowPrimaryButton(
            key: const ValueKey('dating_link_yes'),
            label: loc.dating_linkYes,
            busy: _busy == _LinkBusy.yes,
            onPressed:
                online && _busy == null && requestId != null
                    ? () => _run(
                      _LinkBusy.yes,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .confirm(
                            _keys.keyFor('yes', [_account, requestId, _keep]),
                            requestId,
                            keep: _keep,
                          ),
                    )
                    : null,
          ),
          const SizedBox(height: Spacing.sm),
          FlowSecondaryButton(
            key: const ValueKey('dating_link_not_right_now'),
            label: loc.dating_linkNotRightNow,
            busy: _busy == _LinkBusy.no,
            onPressed:
                online && _busy == null && requestId != null
                    ? () => _run(
                      _LinkBusy.no,
                      () => ref
                          .read(datingLinkGatewayProvider)
                          .decline(requestId),
                    )
                    : null,
          ),
        ],
      ],
    );
  }

  /// Whether the page shows "You decided together." now, and whether it is
  /// still to be marked seen (the asker's, from the server's `moment`).
  bool get _moment =>
      _decided ||
      (_page?.link?.state == DatingLinkState.linked &&
          (_page!.link!.moment || _sentYes));
  bool get _linked => _decided || _page?.link?.state == DatingLinkState.linked;

  /// Fix round 1 (I-1, M-3): Continue, or back once linked: the
  /// Relationship home (the moment marked seen first when it was the
  /// asker's).
  Future<void> _done() async {
    if (_leaving) return;
    _leaving = true;
    final seen = !_decided && (_page?.link?.moment ?? false);
    await datingLinkDone(context, seen: seen);
    if (mounted) _leaving = false;
  }

  Widget _body(AppLocalizations loc) {
    final page = _page;
    if (_decided) {
      return DatingLinkMoment(onContinue: _done);
    }
    if (page == null) return const SizedBox(height: 96);
    if (!page.ok) {
      return switch (page.reason) {
        'reverify_device' => const DatingReverifyLine(),
        // Final client fix (M-4): busy can be tried again, as failed.
        'busy' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DatingCalmLine(loc.dating_busy),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(
              key: const ValueKey('dating_link_try_again'),
              label: loc.dating_tryAgain,
              onPressed: _read,
            ),
          ],
        ),
        'failed' => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
            const SizedBox(height: Spacing.sm),
            FlowSecondaryButton(label: loc.dating_tryAgain, onPressed: _read),
          ],
        ),
        _ => DatingCalmLine(loc.dating_cardGone),
      };
    }
    final name = datingLinkName(loc, page.displayName);
    final link = page.link;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    switch (link?.state) {
      case DatingLinkState.none:
        return _agreeing(loc, name, asker: true);
      case DatingLinkState.askedYou:
        return _agreeing(loc, name, asker: false);
      case DatingLinkState.asked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DatingCalmLine(loc.dating_linkAsked(name)),
            const SizedBox(height: Spacing.md),
            // Fix round 1 (M-5): offline, why Take it back waits.
            if (!online) DatingCalmLine(loc.dating_offline),
            if (_error == 'busy') DatingCalmLine(loc.dating_busy),
            if (_error == 'failed')
              FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
            FlowSecondaryButton(
              key: const ValueKey('dating_link_take_back'),
              label: loc.dating_linkTakeBack,
              busy: _busy == _LinkBusy.back,
              onPressed:
                  online && _busy == null && link?.requestId != null
                      ? () => _run(
                        _LinkBusy.back,
                        () => ref
                            .read(datingLinkGatewayProvider)
                            .cancel(link!.requestId!),
                      )
                      : null,
            ),
          ],
        );
      case DatingLinkState.notReady:
        return DatingCalmLine(loc.dating_linkNotReady(name));
      // Fix round 1 (M-2): the moment only while it is still to show (or
      // this side's own Yes landed); seen already, the chat has ended.
      case DatingLinkState.linked when _moment:
        return DatingLinkMoment(onContinue: _done);
      case DatingLinkState.linked:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DatingCalmLine(loc.dating_chatEnded),
            const SizedBox(height: Spacing.md),
            FlowPrimaryButton(
              key: const ValueKey('dating_link_continue'),
              label: loc.flow_continue,
              onPressed: _done,
            ),
          ],
        );
      case null:
        return DatingCalmLine(loc.dating_cardGone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    // Fix round 1 (M-3, M-8): once linked, back is the Relationship home
    // (as Continue), and the title no longer asks. Final client fix (M-1):
    // the back is this page's alone then, also as the only page (the
    // route's own fallback, the chat, would go first).
    final linked = _linked;
    return AllowLargeText(
      child: DatingOwnBack(
        active: linked,
        onBack: () => unawaited(_done()),
        child: Scaffold(
          appBar: AppBar(
            leading:
                linked
                    ? BackButton(
                      key: const ValueKey('dating_link_back_home'),
                      onPressed: () => unawaited(_done()),
                    )
                    : datingRootBackButton(context),
            title: linked ? null : Text(loc.dating_linkBecome),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.md),
              child: KeyedSubtree(key: ValueKey(_account), child: _body(loc)),
            ),
          ),
        ),
      ),
    );
  }
}
