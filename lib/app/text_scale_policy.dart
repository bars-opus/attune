import 'package:attune/core/flags/public_app_config.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// How far the phone's own text size reaches the app (Spec 1 §2.3, §2.5,
/// §5.1, W10a).
///
/// With `text_scale_v2` off the root clamps every route to 1.0, as it always
/// has. With it on, the root lets the phone's text size through up to
/// [v2Cap] on the routes the W10a audit checked, and keeps 1.0 everywhere
/// else: on the Games routes (no Games file is edited, so their screens keep
/// the size they were built for) and on any route not audited yet (a new
/// route is audited before it gets large text). Screens wrapped in
/// `AllowLargeText` read the phone's size themselves either way.
abstract final class TextScalePolicy {
  /// The root clamp while `text_scale_v2` is off: today's.
  static const double offCap = 1.0;

  /// The root clamp while `text_scale_v2` is on: the highest of 2.0, 1.6 and
  /// 1.3 at which every audited surface, the in-chat Games surfaces
  /// included, passed (W10a Task 8). 1.0 while none of them does.
  ///
  /// 2.0 depends on the owner's two Games lines (their own Games changeset):
  /// the `Flexible` around the section label in `chat_games_sheet.dart`, and
  /// the large tile layout above 1.0 (`> 1.0`) in `game_grid_tile.dart`. If
  /// either is reverted, set this back to 1.0 (the in-chat Games sheet
  /// overflows from 1.3 without them; `in_chat_games_large_text_test.dart`).
  static const double v2Cap = 2.0;

  /// The caps the audit tries, highest first.
  static const List<double> candidateCaps = [2.0, 1.6, 1.3];

  /// Location prefixes of the Games routes in `app_router.dart`: always 1.0.
  /// `test/architecture/text_scale_routes_test.dart` checks this list
  /// against every Games route in the router.
  static const List<String> gameRoutePrefixes = [
    '/thirtySix',
    '/truthOrDare',
    '/customTruthOrDare',
    '/truthReveal',
    '/dareReveal',
    '/thisOrThat',
    '/customQuestion',
    '/mirrorGame',
    '/slidingScaleGame',
    '/scenarioGame',
    '/loveMap',
    '/games/',
  ];

  /// Location prefixes of the routes the W10a audit checked: home (Opinions,
  /// Chat or Me), the Spec 1 screens, chat, Opinions, Together and Planning,
  /// Healing and the journal; Settings is in [auditedLocations]. A prefix
  /// covers its own path and the paths under it (`/planning`,
  /// `/planning/entry`), never a longer name (`/planningX`); one ending in
  /// `/` covers only the paths under it (W10 final W-m2). Every other
  /// route keeps 1.0, including the ones under these screens that no audit
  /// test reaches yet (W10 B6 I-4: language, theme, licences, legal, app
  /// info, blocked and muted, the neutral screen, starred messages, message
  /// search, the ephemeral camera, family members, the anonymous profile,
  /// Opinion engagement and the Opinion loader).
  static const List<String> auditedRoutePrefixes = [
    '/home',
    // Spec 2 W3a: every Dating screen is audited before it lands (§3.0).
    '/dating/',
    '/welcome',
    '/signup',
    '/guest-age',
    '/invite',
    '/invite-partner',
    '/age-stop',
    '/onboarding',
    '/join-invite',
    '/about-us/',
    '/chatScreen',
    '/chat-channel',
    '/chat-media',
    '/image-caption',
    '/video-trim',
    '/streak-camera',
    '/image-viewer',
    '/video-viewer',
    '/ephemeral-video-viewer',
    '/commentThread',
    '/editOpinion',
    '/quoteCompose',
    '/tagBrowse',
    '/together',
    '/planning',
    '/timeline',
    '/couples-calendar/add',
    '/appreciation-jar',
    '/safety-resources',
    '/support/',
    '/healingJourney',
    '/healingStage',
    '/reflectionJournal',
    '/journalEntry',
  ];

  /// Audited by exact location: a child of one of these is not (W10 B6 I-1:
  /// `/settings/download-my-data`, and the past-chapter stories above it,
  /// keep 1.0).
  static const List<String> auditedLocations = [
    '/settings',
    '/settings/safety-pin',
    '/settings/how-you-use-attune',
    '/settings/date-of-birth',
    '/settings/report-child-concern',
    '/settings/signed-in-devices',
    '/settings/quiet',
    '/settings/hidden-periods',
  ];

  /// The boot route `app_router.dart` starts on before its redirect (it
  /// draws nothing): it decides nothing, so the usual start on home doesn't
  /// reflow.
  static const String bootLocation = '/_invisible';

  /// Whether [location] (a matched location such as `/games/snakes/abc`)
  /// keeps 1.0 whatever the flag says: a Games route, or one not audited.
  static bool keepsDefaultSize(String location) =>
      gameRoutePrefixes.any(location.startsWith) ||
      !(auditedLocations.contains(location) ||
          auditedRoutePrefixes.any((p) => _covers(p, location)));

  /// Whether audited prefix [p] covers [location]: the path itself or one
  /// under it, at a `/` boundary.
  static bool _covers(String p, String location) =>
      p.endsWith('/')
          ? location.startsWith(p)
          : location == p || location.startsWith('$p/');

  /// The root clamp for the route on top: [cap] (from [textScaleCapProvider])
  /// on an audited route, else 1.0. With no location at all, or on the boot
  /// route, it is [cap], so the usual start on home doesn't reflow.
  static double capFor({required double cap, required String? topLocation}) {
    if (cap <= offCap) return offCap;
    if (topLocation == null || topLocation == bootLocation) return cap;
    return keepsDefaultSize(topLocation) ? offCap : cap;
  }

  /// The matched location of the GoRouter page on top of [router], pushed
  /// routes included (GoRouter 10 leaves `uri` on the last `go`, so a pushed
  /// Games route would not show there). Before the first match (the very
  /// first frame) it is the location being opened, so a deep link into a
  /// Games route draws no frame at the cap (W10 B6 M-1). The error page
  /// matches nothing too, so it gets the unknown location, which is not
  /// audited (M-2).
  static String? topLocation(GoRouter router) {
    final matches = router.routerDelegate.currentConfiguration;
    if (matches.isEmpty) {
      final opening = router.routeInformationProvider.value.uri.path;
      return opening.isEmpty ? null : opening;
    }
    return matches.last.matchedLocation;
  }
}

/// `text_scale_v2`, effective (the server applies no dependency to it): the
/// live public config, else its cached copy, else off.
final textScaleV2Provider = Provider<bool>((ref) {
  final live = ref.watch(
    publicAppConfigProvider.select((config) => config.valueOrNull?.textScaleV2),
  );
  return live ?? ref.watch(cachedPublicAppConfigProvider)?.textScaleV2 ?? false;
});

/// The root cap: [TextScalePolicy.v2Cap] while `text_scale_v2` is on, else
/// 1.0.
final textScaleCapProvider = Provider<double>(
  (ref) =>
      ref.watch(textScaleV2Provider)
          ? TextScalePolicy.v2Cap
          : TextScalePolicy.offCap,
);

/// The root shell's text clamp. The same widgets whatever the cap (only the
/// number changes), so a flag change mid-session never rebuilds the
/// Navigator below it. It follows the top GoRouter page: a pushed Games route
/// gets 1.0, and popping it brings the cap back once the Games page has
/// finished leaving. Dialogs, sheets and pageless pushes
/// (`Navigator.push(MaterialPageRoute(...))`) take the scale of the page
/// below; an unaudited pageless screen keeps 1.0 with [KeepsDefaultTextSize].
class RootTextScaleClamp extends StatefulWidget {
  const RootTextScaleClamp({
    super.key,
    required this.router,
    required this.cap,
    required this.child,
  });

  final GoRouter router;
  final double cap;
  final Widget child;

  @override
  State<RootTextScaleClamp> createState() => _RootTextScaleClampState();
}

class _RootTextScaleClampState extends State<RootTextScaleClamp> {
  late double _scale = _compute();

  /// A rise waits while a page is leaving (W10 B6 I-2), at most this long
  /// (a screen below that animates forever). MaterialPage's transition is
  /// 300 ms.
  static const Duration _maxRiseWait = Duration(milliseconds: 500);
  bool _risePending = false;
  Duration? _riseSince;

  double _compute() => TextScalePolicy.capFor(
    cap: widget.cap,
    topLocation: TextScalePolicy.topLocation(widget.router),
  );

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_routeChanged);
  }

  @override
  void didUpdateWidget(covariant RootTextScaleClamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.router != widget.router) {
      oldWidget.router.routerDelegate.removeListener(_routeChanged);
      widget.router.routerDelegate.addListener(_routeChanged);
    }
    // A new cap (the flag) or a drop applies at once; a rise with the same
    // cap (a theme, locale or router rebuild while a Games page is leaving)
    // waits for the exit transition like any other (W10 final W-m4).
    final next = _compute();
    if (oldWidget.cap != widget.cap || next < _scale) {
      _scale = next;
    } else if (next > _scale) {
      _waitToRise();
    }
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_routeChanged);
    super.dispose();
  }

  /// The router can announce a new route while the Navigator below is
  /// building (the first route, a redirect); this widget is above it, so the
  /// change waits for the end of that frame. A rise (a Games or 1.0 page is
  /// leaving, by a pop or a `go`) waits until no animation is running, so
  /// the leaving page never draws at the cap during its exit transition; a
  /// drop is at once, so a Games page never draws a frame at the cap.
  void _routeChanged() {
    if (!mounted || _compute() == _scale) return;
    if (_compute() > _scale) {
      _waitToRise();
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scale = _compute());
      });
      return;
    }
    setState(() => _scale = _compute());
  }

  void _waitToRise() {
    if (_risePending) return;
    _risePending = true;
    _riseSince = null;
    SchedulerBinding.instance.addPostFrameCallback(_maybeRise);
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// After each frame: rise once nothing animates (the exit transition has
  /// ended), or after [_maxRiseWait]. Running tickers keep frames coming.
  void _maybeRise(Duration now) {
    if (!mounted) return;
    final since = _riseSince ??= now;
    final next = _compute();
    if (next > _scale &&
        SchedulerBinding.instance.transientCallbackCount > 0 &&
        now - since < _maxRiseWait) {
      SchedulerBinding.instance.addPostFrameCallback(_maybeRise);
      return;
    }
    _risePending = false;
    if (next != _scale) setState(() => _scale = next);
  }

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: _scale,
    child: widget.child,
  );
}

/// Keeps a screen at text size 1.0 whatever the root clamp allows: for a
/// screen pushed with `Navigator.push` (outside GoRouter, so the policy
/// can't see it) that the large-text audit hasn't checked yet. Inert while
/// `text_scale_v2` is off (the root is 1.0 already). Remove it when the
/// screen is audited (W10 B6 I-3).
class KeepsDefaultTextSize extends StatelessWidget {
  const KeepsDefaultTextSize({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    maxScaleFactor: TextScalePolicy.offCap,
    child: child,
  );
}
