/// The reel — the full-screen story viewer (Plan C, Task 4; spec §5.2).
///
/// **A new module.** The streak viewer
/// (`lib/features/chat/presentation/screens/streak_viewer_screen.dart`)
/// is a single-item video player whose only gesture is
/// `onTap: () => _finish()` — no segments, no navigation, no pause, no
/// dismissal gesture, no image branch (spec §5.2's own table). This
/// screen is NOT an adaptation of it: it is new code that reuses only
/// two things by pattern, not by import — signed-media loading (a
/// storage KEY is signed fresh through [storyMediaSignedUrlProvider] on
/// every item, never cached, spec §4.1/§5.5) and `VideoPlayerController`
/// setup/disposal shape. `streak_viewer_screen.dart` itself is untouched
/// by this task.
///
/// ## The player seam
///
/// **There is no platform video decoder in the Flutter test host** —
/// `VideoPlayerController.initialize()` always rejects there
/// (`test/features/chat/ephemeral_video_viewer_screen_test.dart`,
/// `streak_camera_contract_test.dart`'s `_FakeVideoPlayerPlatform`
/// document exactly this). Constructing a `VideoPlayerController`
/// directly inside this screen would make every video test exercise
/// only the error path — "a video runs its natural length" would be
/// unwritable as anything but a tautology.
///
/// So playback sits behind [StoryItemPlayer], an interface this screen
/// drives entirely through duration/position/playing state and a
/// completion callback — never through `VideoPlayerController` itself.
/// [videoPlayerFactory] mints one per video item, mirroring
/// [StoryCameraScreen]'s `videoPreparerFactory`/`imagePreparerFactory`
/// injection shape exactly. The default,
/// [VideoControllerStoryItemPlayer], wraps a real
/// `VideoPlayerController.networkUrl` (the streak viewer's own
/// construction call) and is what production uses; `story_reel_test.dart`
/// injects a fake that reports "initialized" and "ended" on command, with
/// no platform channel involved at all.
///
/// **What this leaves unexercised below the seam:** the real
/// `VideoPlayerController` <-> platform-channel <-> codec path — i.e.
/// whether an actual device decodes a real network video, buffers it,
/// and reports position ticks the way [VideoControllerStoryItemPlayer]
/// assumes. That gap already exists for the streak viewer and the
/// ephemeral video viewer; this task does not close it, it only moves
/// the reel's OWN sequencing/timer/lifecycle logic to the correct side
/// of a seam so that logic — which is where §5.2's rules actually live —
/// is testable without a decoder at all.
///
/// Images have no controller: they hold for [imageHoldDuration] on a
/// plain, pausable [Timer], because a photo has no intrinsic duration to
/// drive the progress bar (spec §5.2).
library;

import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

/// A photo holds for exactly this long (spec §5.2). Not derived from
/// anything server-side — there is no `duration_ms` for an image
/// (`StoryItem.durationMs` is null for `mediaType == 'image'`).
const Duration kStoryImageHoldDuration = Duration(seconds: 5);

/// How often the reel's own clock ticks to update the progress bar.
/// Independent of the underlying player: for a video this is purely a
/// UI refresh rate, not what drives playback (the player drives itself).
const Duration kStoryProgressTickInterval = Duration(milliseconds: 100);

/// What the reel needs from a playing item, independent of whether it is
/// backed by a real `VideoPlayerController` or a test fake. See this
/// file's header for why this seam exists.
abstract class StoryItemPlayer {
  /// Prepares the item for playback (analogous to
  /// `VideoPlayerController.initialize()`). Must complete before
  /// [duration]/[position] are meaningful.
  Future<void> initialize();

  /// Total playback length. Only valid after [initialize] completes.
  Duration get duration;

  /// Current playback position.
  Duration get position;

  void play();

  void pause();

  /// Fires exactly once, when playback reaches the end naturally. Not
  /// fired by [pause] or [dispose].
  Stream<void> get onEnded;

  Future<void> dispose();
}

/// Production [StoryItemPlayer]: wraps a real `VideoPlayerController`,
/// constructed and disposed the same way the streak viewer does
/// (`VideoPlayerController.networkUrl` + `initialize()` + a listener that
/// latches on end-of-clip so it cannot fire twice — mirrored from
/// `streak_viewer_screen.dart`'s own `_playAt`).
class VideoControllerStoryItemPlayer implements StoryItemPlayer {
  VideoControllerStoryItemPlayer(Uri uri)
    : _controller = VideoPlayerController.networkUrl(uri);

  final VideoPlayerController _controller;
  final _endedController = StreamController<void>.broadcast();
  bool _ended = false;

  /// Exposed so [_MediaView] can hand the real controller to Flutter's
  /// `VideoPlayer` widget for actual rendering — the ONE place this
  /// screen needs the concrete type rather than the [StoryItemPlayer]
  /// abstraction, since there is no generic "render a frame" concept on
  /// the seam itself.
  VideoPlayerController get controller => _controller;

  @override
  Future<void> initialize() async {
    await _controller.initialize();
    _controller.addListener(_onTick);
  }

  void _onTick() {
    if (_ended) return;
    final value = _controller.value;
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !value.isPlaying) {
      _ended = true;
      if (!_endedController.isClosed) _endedController.add(null);
    }
  }

  @override
  Duration get duration => _controller.value.duration;

  @override
  Duration get position => _controller.value.position;

  @override
  void play() => unawaited(_controller.play());

  @override
  void pause() => unawaited(_controller.pause());

  @override
  Stream<void> get onEnded => _endedController.stream;

  @override
  Future<void> dispose() async {
    _controller.removeListener(_onTick);
    await _endedController.close();
    await _controller.dispose();
  }
}

/// Opens at the OLDEST active item of one author's page (spec §5.5:
/// "the active reel opens at the oldest active item"). Viewed segments
/// are faded (handled by [StoryProgressBars]'s already-filled bars for
/// `i < currentIndex`; a segment the viewer has already seen from a
/// previous visit is NOT skipped — this screen still plays it, just
/// starting the walk at the oldest item every open, matching the
/// ring's own "faded, not hidden" posture, spec §5.5).
class StoryReelScreen extends ConsumerStatefulWidget {
  /// Author mode (Task 4's original shape, unchanged): one author's
  /// active reel via [storyReelPagesProvider] (`list_active_story_items`,
  /// EXCLUDES expired items). [authorId] is required and [isOwnReel] is a
  /// static, caller-supplied flag because the ring/reel entry point
  /// already knows the single author before opening this screen.
  const StoryReelScreen({
    super.key,
    required this.relationshipId,
    required this.authorId,
    this.isOwnReel = false,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
  }) : occurredOn = null;

  /// Day mode (Task 5, spec §5.3): one calendar day's items via
  /// [storyDayItemsProvider] (`list_story_day_items`, INCLUDES expired
  /// items — the whole point of expiry hiding rather than deleting,
  /// spec §3.2). A day can mix both partners' items, so there is no
  /// single [isOwnReel] answer for the whole screen; per-item authorship
  /// is derived from [currentUserProvider] inside [_maybeMarkViewed]
  /// instead. [authorId] is not used in this mode.
  ///
  /// This constructor is additive: it does not change what author mode
  /// consumes or how it behaves, and `story_reel_test.dart`'s suite
  /// (Task 4) exercises only the first constructor, unmodified.
  const StoryReelScreen.forDay({
    super.key,
    required this.relationshipId,
    required this.occurredOn,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
  }) : authorId = '',
       isOwnReel = false;

  final String relationshipId;
  final String authorId;

  /// True when [authorId] is the caller's own id. `mark_story_viewed`
  /// refuses the author (spec §5.2: "the author's own preview" does not
  /// count), so this screen never even attempts the call for its own
  /// reel — see [_maybeMarkViewed]. Only meaningful in author mode
  /// (`occurredOn == null`); day mode ignores this field entirely.
  final bool isOwnReel;

  /// Non-null selects day mode (spec §5.3). Null (the default,
  /// author-mode constructor) is Task 4's original behaviour, byte-for-
  /// byte: the same provider is watched, keyed the same way.
  final DateTime? occurredOn;

  /// Test seam: mints a [StoryItemPlayer] for a video item's signed URL.
  /// Defaults to [VideoControllerStoryItemPlayer]. See this file's header.
  final StoryItemPlayer Function(Uri uri)? videoPlayerFactory;

  /// Test seam so the 5-second image hold can be asserted against a
  /// smaller number without weakening what production uses (which stays
  /// at [kStoryImageHoldDuration] by default).
  final Duration imageHoldDuration;

  @override
  ConsumerState<StoryReelScreen> createState() => _StoryReelScreenState();
}

class _StoryReelScreenState extends ConsumerState<StoryReelScreen> {
  int _index = 0;
  Timer? _tickTimer;
  StoryItemPlayer? _player;
  StreamSubscription<void>? _endedSub;

  /// Elapsed time within the current item, advanced by [_tickTimer] for
  /// an image and read from the player for a video. Drives
  /// [StoryProgressBars.currentProgress].
  Duration _elapsed = Duration.zero;
  Duration _currentDuration = kStoryImageHoldDuration;

  /// True while the user is actively holding a press (spec: hold pauses).
  /// Cleared on release, independent of [_lifecyclePaused] — see
  /// [_paused]'s doc comment (fix round 1, F1).
  bool _heldPaused = false;

  /// True while the app is backgrounded (spec/brief: "backgrounding
  /// mid-item pauses rather than skips"). Cleared automatically when the
  /// app returns to the foreground (fix round 1, F1) — kept SEPARATE
  /// from [_heldPaused] so a resume can clear its own cause of pausing
  /// without accidentally resuming a hold the user is still applying (a
  /// backgrounding mid-hold — e.g. a notification banner while the
  /// finger is still down — should leave the hold in control on return,
  /// not silently un-pause under the user's finger).
  bool _lifecyclePaused = false;

  /// The combined pause state that actually gates the ticker/player —
  /// paused while EITHER cause is active. Fix round 1, F1: the original
  /// single `_paused` flag was set by `_setForeground(false)` and only
  /// ever cleared by `onHoldEnd`, so a lifecycle pause with no matching
  /// hold-release could never be cleared — the reel froze permanently
  /// after any backgrounding. Foreground/hold now each own and clear
  /// their own half.
  bool get _paused => _heldPaused || _lifecyclePaused;

  bool _loadingItem = false;

  /// Set once the current item has actually rendered — an image after
  /// its bytes resolve, a video after [StoryItemPlayer.initialize]
  /// succeeds. [_maybeMarkViewed] is a no-op until this is true (spec
  /// §5.2: "after a partner's active item renders successfully" — never
  /// on open, never on a failed load).
  bool _rendered = false;

  /// The signed URL `_startItemAsync` minted for the CURRENT item.
  /// Fix round 1, F5: previously `_MediaView` minted its OWN second URL
  /// via `storyMediaSignedUrlProvider` instead of using this one — one
  /// wasted round-trip per image, and a real risk of disagreement
  /// between "the URL that gated the render/mark check" and "the URL
  /// actually rendered." Reset to null on every item change so a stale
  /// URL from the previous item is never shown while the next one loads.
  String? _currentSignedUrl;

  /// Guards a single `mark_story_viewed` call per item id, the same
  /// shape as the streak viewer's `_viewSpent` guard for its own
  /// once-only server call.
  final Set<String> _markedItemIds = {};

  /// Bumped on every item change/dispose so a callback from an item the
  /// user has since left (advanced past, backgrounded across, or that
  /// this screen has been popped from) cannot mutate current state —
  /// this task's own "guard every post-await state write" requirement,
  /// following Task 2's F1/F2 lesson.
  int _generation = 0;

  AppLifecycleListener? _lifecycleListener;
  bool _appForeground = true;

  /// Task 6 (spec §5.4): composing a reply to the CURRENT item. Owns its
  /// own controller/focus node rather than reusing chat's composer —
  /// this screen sends directly through [chatRepositoryProvider], not
  /// through chatControllerProvider/the outbox (§6.1's story outbox is
  /// for POSTING a story, an entirely separate queue; a reply is an
  /// ordinary `messages` insert per §5.4's own opening rationale, and
  /// this screen is a lightweight, foreground-only surface with nothing
  /// like the streak/story capture flow's offline requirements).
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _sendingReply = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onPause: () => _setForeground(false),
      onInactive: () => _setForeground(false),
      onHide: () => _setForeground(false),
    );
    // Composing a reply pauses the reel exactly like a hold — the item
    // must not advance or expire the progress bar out from under a
    // partially-typed reply.
    _replyFocusNode.addListener(() {
      if (!mounted) return;
      _setHeldPaused(_replyFocusNode.hasFocus);
    });
  }

  void _setForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (!foreground) {
      // Backgrounding mid-item PAUSES rather than skips (spec/brief):
      // the timer/player simply stops advancing; nothing advances the
      // index, and nothing is lost.
      _setLifecyclePaused(true);
    } else {
      // Fix round 1, F1: returning to the foreground RESUMES — the
      // spec's own table names "Lifecycle pause/RESUME" as one
      // requirement, and the brief's wording ("pauses rather than
      // skipping") bounds what backgrounding may do, not what
      // foregrounding must NOT do. A prior version left this branch
      // empty on the theory that resume should require an explicit
      // tap, but no such tap existed anywhere in the gesture set — a
      // plain tap navigates — so every backgrounding (including a
      // routine `inactive` blip from a Control Centre pull or an
      // incoming-call banner) froze the reel until the user happened
      // to long-press. Clearing the lifecycle half here leaves a
      // concurrent HELD pause in control via `_paused`'s OR — see that
      // getter's doc comment.
      _setLifecyclePaused(false);
    }
  }

  void _startItem(List<StoryItem> items, int index) {
    unawaited(_startItemAsync(items, index));
  }

  Future<void> _startItemAsync(List<StoryItem> items, int index) async {
    _tickTimer?.cancel();
    _tickTimer = null;
    // NOT awaited: this can run from INSIDE _endedSub's own onEnded
    // callback (onEnded -> _advance -> _startItem -> here), and
    // StreamSubscription.cancel() on a broadcast controller does not
    // complete until the event delivery that triggered it finishes —
    // awaiting it here from inside that same delivery deadlocks (the
    // microtask that would complete it never runs because this call
    // stack is blocking on it). Fire-and-forget mirrors dispose()'s own
    // unawaited cancel below.
    unawaited(_endedSub?.cancel());
    _endedSub = null;
    final oldPlayer = _player;
    _player = null;
    if (oldPlayer != null) unawaited(oldPlayer.dispose());

    final generation = ++_generation;
    setState(() {
      _index = index;
      _elapsed = Duration.zero;
      _rendered = false;
      _loadingItem = true;
      // A hold never carries across an item transition — releasing is
      // meaningless once the item it applied to is gone. Deliberately
      // NOT clearing _lifecyclePaused here (fix round 1, F1): if the
      // app is still backgrounded when an item transition happens
      // (e.g. a video's onEnded fires while backgrounded), the new
      // item must start paused too, not slip into playing while nobody
      // can see it.
      _heldPaused = false;
      _currentDuration = kStoryImageHoldDuration;
      // Fix round 1, F5: clear the previous item's URL immediately so
      // a slow next-item fetch never shows a stale image behind the
      // loading spinner.
      _currentSignedUrl = null;
    });
    // Fix round 1, F8: a live announcement on every item change, in
    // addition to StoryProgressBars' own static "Story N of M"
    // Semantics label — a screen-reader user who just performed the
    // "advance"/"go back" action hears where they landed immediately,
    // rather than needing to re-navigate onto the progress bar to
    // discover it.
    unawaited(
      SemanticsService.announce(
        'Story ${index + 1} of ${items.length}',
        TextDirection.ltr,
      ),
    );

    final item = items[index];
    final gateway = ref.read(storyReadGatewayProvider);
    final signedUrl = await gateway.signMediaUrl(item.mediaKey);
    if (!mounted || generation != _generation) return;

    if (signedUrl == null) {
      // Nothing to render. Treat like the streak viewer's "clips are
      // gone" branch: do not mark viewed (spec: only after a successful
      // render), surface the failure, and let the viewer navigate away
      // manually rather than auto-advancing past a real gap.
      setState(() {
        _loadingItem = false;
        _rendered = false;
      });
      return;
    }

    if (item.mediaType == 'video') {
      final factory = widget.videoPlayerFactory ?? _defaultVideoPlayerFactory;
      final player = factory(Uri.parse(signedUrl));
      try {
        await player.initialize();
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _loadingItem = false);
        }
        await player.dispose();
        return;
      }
      if (!mounted || generation != _generation) {
        await player.dispose();
        return;
      }

      _player = player;
      _endedSub = player.onEnded.listen((_) {
        if (!mounted || generation != _generation) return;
        unawaited(_advance(items, generation));
      });

      setState(() {
        _loadingItem = false;
        _rendered = true;
        _currentDuration = player.duration;
      });
      // Only actually start playback if nothing is currently pausing
      // the reel (fix round 1, F1) — a video whose onEnded fired while
      // the app is backgrounded must not start the NEXT item playing
      // out of sight.
      if (!_paused) player.play();
      _startTicker(generation, items);
      unawaited(_maybeMarkViewed(item));
    } else {
      // Image: no controller, no natural duration. Hold for
      // widget.imageHoldDuration on a plain Timer (spec §5.2).
      setState(() {
        _loadingItem = false;
        _rendered = true;
        _currentDuration = widget.imageHoldDuration;
        // Fix round 1, F5: this IS the URL _MediaView renders — no
        // second mint. Set only once we've already confirmed it
        // non-null above, so `_rendered` and `_currentSignedUrl` agree
        // by construction.
        _currentSignedUrl = signedUrl;
      });
      _startTicker(generation, items);
      unawaited(_maybeMarkViewed(item));
    }

    // Fix round 1, F6: named explicitly in spec §5.2's table ("New in
    // the reel: next-item preloading") and this task's own Step 3.
    // Warming the NEXT item's signed URL/image bytes while the CURRENT
    // one is playing means tap-right usually lands on already-fetched
    // media instead of a fresh storage round-trip. Only ever warms a
    // cache Flutter/the image pipeline already owns (`precacheImage`)
    // or a Riverpod `.future` a future rebuild can re-await — nothing
    // here stores a signed URL past this call, so it does not create a
    // second "hold a URL" path alongside `_currentSignedUrl` above.
    _preloadNextItem(items, index);
  }

  /// Best-effort warm-up for `items[index + 1]`, if it exists and is an
  /// image (a video's warm-up would mean constructing and initializing
  /// a whole second [StoryItemPlayer]/[VideoPlayerController] ahead of
  /// time, which is a materially bigger change than this fix round's
  /// scope — see this task's report for that call). Failures are
  /// swallowed: this is a pure optimization, never a correctness path,
  /// so nothing here may throw into an unguarded context or affect
  /// `_rendered`/`markViewed` for the CURRENT item.
  void _preloadNextItem(List<StoryItem> items, int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= items.length) return;
    final next = items[nextIndex];
    if (next.mediaType != 'image') return;

    unawaited(() async {
      try {
        final url = await ref.read(storyReadGatewayProvider).signMediaUrl(
          next.mediaKey,
        );
        if (url == null || !mounted) return;
        await precacheImage(
          NetworkImage(url),
          context,
          // A failed preload must not surface as an app-visible error —
          // it is a pure optimization, and the normal fetch path in
          // _startItemAsync runs again when the viewer actually reaches
          // this item. Without an explicit onError, precacheImage routes
          // a decode/network failure through FlutterError.reportError,
          // which flutter_test treats as a test failure even though the
          // error itself is marked `silent: true` — this onError is
          // required, not merely tidy, to keep this best-effort warm-up
          // from ever failing a caller's test or surfacing a red error
          // banner in a real app.
          onError: (_, __) {},
        );
      } catch (_) {
        // Best-effort only — a failed preload is invisible to the
        // user; the normal fetch path in _startItemAsync runs again
        // when they actually reach this item.
      }
    }());
  }

  StoryItemPlayer _defaultVideoPlayerFactory(Uri uri) =>
      VideoControllerStoryItemPlayer(uri);

  void _startTicker(int generation, List<StoryItem> items) {
    _tickTimer?.cancel();
    // Fix round 1, F7: the completion/auto-advance TIMING must stay
    // real regardless of this setting — an image still needs to hold
    // for its actual duration and a video still needs its actual
    // length, reduce-motion or not (spec §5.2 makes no exception for
    // it). What reduce-motion removes is the smooth ~10Hz VISUAL fill:
    // `story_ring.dart` (this same feature's sibling widget) collapses
    // its own animated primitive to a static end-state under
    // `disableAnimations` rather than removing the affordance — this
    // ticker follows the identical posture by tracking `_elapsed`
    // every tick (so completion detection is unaffected) but only
    // repainting the progress bar at item start and at completion, not
    // on every intermediate tick.
    final reduceMotion = mounted
        ? MediaQuery.of(context).disableAnimations
        : false;
    _tickTimer = Timer.periodic(kStoryProgressTickInterval, (_) {
      if (!mounted || generation != _generation || _paused) return;

      final player = _player;
      final elapsed = player != null
          ? player.position
          : _elapsed + kStoryProgressTickInterval;

      if (elapsed >= _currentDuration) {
        // For an image the timer itself reaching the hold duration is
        // the completion signal; for a video, StoryItemPlayer.onEnded
        // is (that listener already calls _advance) — but a slow tick
        // that observes position >= duration first is harmless to catch
        // here too, now that _advance itself is generation-guarded (fix
        // round 1, F2).
        setState(() => _elapsed = _currentDuration);
        if (player == null) unawaited(_advance(items, generation));
        return;
      }

      if (reduceMotion) {
        // Track time without an intermediate repaint — the segment
        // stays visually at its start-of-item state until the jump to
        // fully-filled above, rather than smoothly animating.
        _elapsed = elapsed;
      } else {
        setState(() => _elapsed = elapsed);
      }
    });
  }

  /// The user's own hold/release (fix round 1, F1: split from
  /// [_setLifecyclePaused] so each cause of pausing can clear itself
  /// without stepping on the other — see [_paused]'s doc comment).
  void _setHeldPaused(bool paused) {
    if (_heldPaused == paused) return;
    final wasPaused = _paused;
    setState(() => _heldPaused = paused);
    _applyPausedTransition(wasPaused);
  }

  /// The app foreground/background transition's own half of the pause
  /// state (fix round 1, F1).
  void _setLifecyclePaused(bool paused) {
    if (_lifecyclePaused == paused) return;
    final wasPaused = _paused;
    setState(() => _lifecyclePaused = paused);
    _applyPausedTransition(wasPaused);
  }

  /// Drives the actual player/ticker effect off the COMBINED [_paused]
  /// state, only when it actually changed between the two setters
  /// above — e.g. backgrounding while already held-paused must not
  /// call `player.pause()` a second time, and foregrounding while still
  /// held-paused must not call `player.play()` while the user's finger
  /// is still down.
  void _applyPausedTransition(bool wasPaused) {
    final isPaused = _paused;
    if (wasPaused == isPaused) return;
    final player = _player;
    if (player == null) return;
    if (isPaused) {
      player.pause();
    } else {
      player.play();
    }
  }

  Future<void> _maybeMarkViewed(StoryItem item) async {
    // Never for the author's own reel (mark_story_viewed refuses the
    // author server-side, spec §5.2/§3.4) and never twice for the same
    // item.
    //
    // Author mode (occurredOn == null) uses the caller-supplied static
    // flag, unchanged from Task 4. Day mode has no single answer for
    // the whole screen — a day can mix both partners' items — so it
    // derives "is this item mine" per item from the signed-in user
    // instead. Either way, an EXPIRED item reaching this point is still
    // attempted: the server itself is the authority that refuses a view
    // for `expires_at <= now()` (spec §3.4/§8, "viewing an expired story
    // from the calendar does not record a view") — this client
    // deliberately does not duplicate that date check, matching this
    // file's existing posture of trusting the RPC contract rather than
    // re-deriving expiry client-side.
    final isOwn = widget.occurredOn != null
        ? item.authorId == ref.read(currentUserProvider)?.id
        : widget.isOwnReel;
    if (isOwn) return;
    if (_markedItemIds.contains(item.id)) return;
    _markedItemIds.add(item.id);
    final generation = _generation;
    try {
      await ref.read(storyReadGatewayProvider).markViewed(storyItemId: item.id);
    } catch (_) {
      // Best-effort, same posture as the streak viewer's own
      // _spendView catch: a failed mark must not trap the viewer or
      // retry-loop here. Allow a retry on a future open by un-marking —
      // but only if this is still the live item/screen (generation
      // guard), since a stale failure for an item the user has already
      // left must not perturb current state.
      if (mounted && generation == _generation) {
        _markedItemIds.remove(item.id);
      }
    }
  }

  /// Advances to the next item — the ONLY place `_index` moves forward.
  ///
  /// [fromGeneration] must be the generation the CALLER observed as
  /// current at the moment it decided to advance (the `onEnded`
  /// listener's own captured `generation`, the tick timer's own, or
  /// `_generation` read fresh at tap time). Fix round 1, F2: a caller
  /// that captured no generation at all let two calls landing in the
  /// same frame (a video's `onEnded` firing in the same frame as a
  /// tap-right) each read the SAME pre-advance `_index` and each start a
  /// real advance — `_startItem` writes `_index`/bumps `_generation`
  /// synchronously, so the second call to run additionally skipped
  /// straight past the item the first call had just started, silently
  /// marking an item viewed that was never rendered for even one frame.
  /// Checking `fromGeneration == _generation` at the top makes the
  /// second call a no-op: whichever call runs first bumps `_generation`
  /// via `_startItem`, so the second call's stale generation no longer
  /// matches and it returns immediately instead of advancing again.
  Future<void> _advance(List<StoryItem> items, int fromGeneration) async {
    if (fromGeneration != _generation) return;

    if (_index + 1 < items.length) {
      _startItem(items, _index + 1);
      return;
    }
    return _advanceAtEndOfPage(items, fromGeneration);
  }

  /// Test-only seam for fix round 1, F2's exact race: two callers who
  /// both captured the SAME (soon-to-be-stale) generation calling
  /// `_advance` back-to-back with no await between them — reproducing
  /// "a video's `onEnded` firing in the same frame as a tap-right" (or
  /// any other two callers that captured `_generation` at the same
  /// moment) without needing to force that exact timing through the
  /// public gesture-testing API, which fully settles each dispatched
  /// gesture (including any interleaved stream microtask) before
  /// returning control to the test — meaning two `tester.tap()` calls
  /// are provably sequential, never actually concurrent, and cannot
  /// exercise this guard at all. `@visibleForTesting` mirrors
  /// `StreakViewerScreen.finishForTest()`'s own precedent for exactly
  /// this problem (a private State needs a test-only entry point for a
  /// timing condition the public widget API cannot force), invoked via
  /// `(state as dynamic).raceAdvanceForTest(...)` the same way that
  /// file's own test does.
  @visibleForTesting
  Future<void> raceAdvanceForTest(List<StoryItem> items) async {
    final generation = _generation;
    unawaited(_advance(items, generation));
    unawaited(_advance(items, generation));
  }

  Future<void> _advanceAtEndOfPage(
    List<StoryItem> items,
    int fromGeneration,
  ) async {
    // Fix round 1, F3: reaching the end of the currently-loaded PAGE is
    // not necessarily the end of the reel — list_active_story_items
    // pages at 50 (spec §5.5) and an author can post more than that in
    // 24h (spec §7: "no posting limit"). Closing here unconditionally
    // made item 51+ permanently unreachable and left the partner's ring
    // stuck unviewed with no way to clear it. `storyReelPagesProvider`/
    // `storyDayItemsProvider` already implement the keyset walk; this
    // only ever CALLS `loadMore()` on whichever one backs this screen,
    // never re-implements paging.
    if (!_pagerHasMore()) {
      _close();
      return;
    }

    // Show the loading state rather than a dead end or a flicker while
    // the next page is in flight.
    setState(() => _loadingItem = true);
    await _pagerLoadMore();
    if (!mounted || fromGeneration != _generation) return;

    final refreshed = _pagerCurrentItems() ?? items;
    if (_index + 1 < refreshed.length) {
      _startItem(refreshed, _index + 1);
    } else {
      // loadMore() returned a short/empty page — genuinely no more
      // items despite hasMore having been true a moment ago (e.g. the
      // very last page). Close rather than spin forever.
      setState(() => _loadingItem = false);
      _close();
    }
  }

  /// The three operations F3 needs on "whichever keyset pager backs
  /// this screen" (`StoryReelPagesNotifier` in author mode,
  /// `StoryDayItemsNotifier` in day mode). Both extend a shared private
  /// base in `story_providers.dart` that is not exported, so this
  /// screen branches on `widget.occurredOn` and talks to each concrete
  /// notifier type directly rather than widening that base's visibility
  /// just for these three calls.
  bool _pagerHasMore() {
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref
          .read(
            storyDayItemsProvider(
              StoryDayKey(
                relationshipId: widget.relationshipId,
                occurredOn: occurredOn,
              ),
            ).notifier,
          )
          .hasMore;
    }
    return ref
        .read(
          storyReelPagesProvider(
            StoryReelKey(
              relationshipId: widget.relationshipId,
              authorId: widget.authorId,
            ),
          ).notifier,
        )
        .hasMore;
  }

  Future<void> _pagerLoadMore() {
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref
          .read(
            storyDayItemsProvider(
              StoryDayKey(
                relationshipId: widget.relationshipId,
                occurredOn: occurredOn,
              ),
            ).notifier,
          )
          .loadMore();
    }
    return ref
        .read(
          storyReelPagesProvider(
            StoryReelKey(
              relationshipId: widget.relationshipId,
              authorId: widget.authorId,
            ),
          ).notifier,
        )
        .loadMore();
  }

  List<StoryItem>? _pagerCurrentItems() {
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref
          .read(
            storyDayItemsProvider(
              StoryDayKey(
                relationshipId: widget.relationshipId,
                occurredOn: occurredOn,
              ),
            ),
          )
          .valueOrNull;
    }
    return ref
        .read(
          storyReelPagesProvider(
            StoryReelKey(
              relationshipId: widget.relationshipId,
              authorId: widget.authorId,
            ),
          ),
        )
        .valueOrNull;
  }

  void _retreat(List<StoryItem> items) {
    if (_index > 0) {
      _startItem(items, _index - 1);
    }
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  /// Shows the "this cannot be undone" confirmation the brief requires,
  /// then calls `delete_story_item`. Mirrors the house pattern already
  /// used for deleting a timeline moment
  /// (`moment_card.dart`'s `_showDeleteConfirmation` — same title/body
  /// copy shape) rather than inventing a new confirmation style.
  ///
  /// Deletion removes the item from BOTH surfaces at once (spec §3.1/
  /// §3.2: one row, one `deleted_at`) — this screen does not need to
  /// separately invalidate the ring/reel provider; the server bumps
  /// `story_change_signals` on soft delete (spec §5.5) and every
  /// provider watching it (including `storyReelPagesProvider` for this
  /// same author, if the ring is still mounted elsewhere) refetches on
  /// its own. This screen only needs to refresh ITS OWN day-items page
  /// and step off the now-gone item.
  Future<void> _confirmAndDelete(
    StoryItem item,
    List<StoryItem> items,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text(
          'This removes it from the reel and the calendar permanently. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(storyReadGatewayProvider).deleteItem(storyItemId: item.id);
    } catch (_) {
      // Best-effort surface: if the RPC refuses (e.g. a race where the
      // item was already gone), there is nothing actionable to retry
      // here beyond leaving the viewer as-is; the next refetch/signal
      // reflects true server state either way.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this story.')),
        );
      }
      return;
    }
    if (!mounted) return;

    // Step off the deleted item before the page refreshes out from
    // under the current index: if it was the last item, close; else
    // stay at the same index (the next item slides into its place once
    // the day-items page reloads without the deleted row).
    if (items.length <= 1) {
      _close();
    } else if (_index >= items.length - 1) {
      _startItem(items, items.length - 2);
    }

    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      unawaited(
        ref
            .read(
              storyDayItemsProvider(
                StoryDayKey(
                  relationshipId: widget.relationshipId,
                  occurredOn: occurredOn,
                ),
              ).notifier,
            )
            .refresh(),
      );
    }
  }

  @override
  void dispose() {
    _generation++;
    _tickTimer?.cancel();
    unawaited(_endedSub?.cancel());
    unawaited(_player?.dispose());
    _lifecycleListener?.dispose();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  /// Sends a chat message quoting [item] — Task 6, spec §5.4. Composes
  /// through [chatRepositoryProvider].sendTextMessage directly (not
  /// chatControllerProvider): this screen has no chat conversation/outbox
  /// context of its own, and a reply from the reel is a single
  /// foreground-only send, not something that needs offline queueing —
  /// if it fails, the text stays in the field and the user can retry
  /// (mirrors this screen's own _confirmAndDelete's "best-effort, no
  /// retry loop" posture for its own single RPC call).
  ///
  /// Deliberately does NOT send `quotedText` — only `storyItemId`. The
  /// server trigger (20260939010000_story_replies.sql) overwrites
  /// quoted_text from the story's own media_type regardless of what a
  /// client sends, and spec §5.4 is explicit the client must not try to
  /// set its own; SupabaseChatRepository.sendTextMessage additionally
  /// omits the key outright when storyItemId is set, but not sending a
  /// value here keeps the intent visible at the call site too.
  Future<void> _sendReply(StoryItem item) async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _sendingReply) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _sendingReply = true);
    final generation = _generation;
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            relationshipId: widget.relationshipId,
            senderId: user.id,
            clientMessageId: const Uuid().v4(),
            content: text,
            storyItemId: item.id,
          );
      // Guard every post-await state write (Task 2's F1/F2 lesson): both
      // `mounted` (this screen may have been popped while the request
      // was in flight) and the generation token (the user may have
      // advanced/retreated to a different item, whose reply this send
      // must not be mistaken for clearing).
      if (!mounted || generation != _generation) return;
      _replyController.clear();
      _replyFocusNode.unfocus();
      setState(() => _sendingReply = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent')),
      );
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _sendingReply = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send your reply.')),
      );
    }
  }

  double get _progressFraction {
    if (_currentDuration == Duration.zero) return 1.0;
    return (_elapsed.inMilliseconds / _currentDuration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final occurredOn = widget.occurredOn;
    // Day mode (spec §5.3) watches the day-scoped, expired-inclusive
    // provider; author mode watches the exact same
    // storyReelPagesProvider(key) Task 4 already wired — unchanged.
    final pagesAsync = occurredOn != null
        ? ref.watch(
            storyDayItemsProvider(
              StoryDayKey(
                relationshipId: widget.relationshipId,
                occurredOn: occurredOn,
              ),
            ),
          )
        : ref.watch(
            storyReelPagesProvider(
              StoryReelKey(
                relationshipId: widget.relationshipId,
                authorId: widget.authorId,
              ),
            ),
          );

    return Scaffold(
      backgroundColor: Colors.black,
      body: pagesAsync.when(
        loading: () => const _CenteredSpinner(),
        error: (error, _) => _ErrorState(onClose: _close),
        data: (items) {
          if (items.isEmpty) return _EmptyState(onClose: _close);
          // Open at the OLDEST active item on first build only — items
          // arrive already oldest-first (spec §5.5), so index 0 IS the
          // oldest; this only needs to kick off playback once.
          if (_index == 0 && !_loadingItem && !_rendered && _player == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startItem(items, 0);
            });
          }
          final clampedIndex = _index.clamp(0, items.length - 1);
          // Deletion lives in the calendar's day view, author-only (spec
          // §5.3: "this is where deletion-from-the-past lives, and it is
          // author-only"). `delete_story_item` is enforced author-only
          // server-side regardless, but the brief requires the UI not even
          // OFFER an action that will be refused — so this is gated on
          // BOTH day mode and the CURRENT item's own author, never a
          // static per-screen flag (a day can mix both partners' items).
          final currentItem = items[clampedIndex];
          final myId = ref.read(currentUserProvider)?.id;
          final canDeleteCurrent =
              occurredOn != null && myId != null && currentItem.authorId == myId;
          // Replying is only offered on the PARTNER's item — replying to
          // your own story would quote yourself in your own chat, which
          // is not a sensible action and nothing in the spec asks for
          // it. Same per-item (not per-screen) derivation canDeleteCurrent
          // uses, since day mode can mix both partners' items.
          final isCurrentMine = occurredOn != null
              ? myId != null && currentItem.authorId == myId
              : widget.isOwnReel;
          return _ReelBody(
            items: items,
            index: clampedIndex,
            progress: _progressFraction,
            loading: _loadingItem,
            player: _player,
            signedUrl: _currentSignedUrl,
            onTapLeft: () => _retreat(items),
            onTapRight: () => unawaited(_advance(items, _generation)),
            onHoldStart: () => _setHeldPaused(true),
            onHoldEnd: () => _setHeldPaused(false),
            onDismiss: _close,
            onDelete: canDeleteCurrent
                ? () => unawaited(_confirmAndDelete(currentItem, items))
                : null,
            canReply: !isCurrentMine,
            replyController: _replyController,
            replyFocusNode: _replyFocusNode,
            sendingReply: _sendingReply,
            onSendReply: () => unawaited(_sendReply(currentItem)),
          );
        },
      ),
    );
  }
}

class _ReelBody extends StatelessWidget {
  const _ReelBody({
    required this.items,
    required this.index,
    required this.progress,
    required this.loading,
    required this.player,
    required this.signedUrl,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onDismiss,
    this.onDelete,
    this.canReply = false,
    this.replyController,
    this.replyFocusNode,
    this.sendingReply = false,
    this.onSendReply,
  });

  final List<StoryItem> items;
  final int index;
  final double progress;
  final bool loading;
  final StoryItemPlayer? player;

  /// The signed URL the screen already minted for the CURRENT item
  /// (fix round 1, F5) — passed straight to [_MediaView] rather than
  /// having it re-fetch its own.
  final String? signedUrl;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onDismiss;

  /// Non-null only when the CURRENT item's author is the signed-in user
  /// AND this reel is in day mode (spec §5.3: calendar deletion is
  /// author-only). Null hides the affordance entirely rather than
  /// showing it disabled — the brief requires the UI not offer an
  /// action `delete_story_item` would refuse server-side.
  final VoidCallback? onDelete;

  /// Task 6 (spec §5.4): true only for the PARTNER's current item —
  /// replying to your own story is not offered. Gates whether the reply
  /// composer renders at all.
  final bool canReply;
  final TextEditingController? replyController;
  final FocusNode? replyFocusNode;
  final bool sendingReply;
  final VoidCallback? onSendReply;

  /// True once a press has been held long enough to count as "hold to
  /// pause" rather than a tap. A single [GestureDetector] drives both —
  /// nesting a nav-tap detector inside a separate hold/dismiss detector
  /// left them fighting over the same pointer in the gesture arena, so
  /// this widget resolves press/tap/drag itself instead: `onTapDown`
  /// starts a short timer; if it fires before `onTapUp`/`onTapCancel`,
  /// the press counts as a hold (pause) rather than a tap (navigate).
  static const _holdThreshold = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final item = items[index];
    return _GestureLayer(
      holdThreshold: _holdThreshold,
      onHoldStart: onHoldStart,
      onHoldEnd: onHoldEnd,
      onTapLeft: onTapLeft,
      onTapRight: onTapRight,
      onDismiss: onDismiss,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: loading
                ? const CircularProgressIndicator(color: Colors.white)
                : _MediaView(item: item, player: player, signedUrl: signedUrl),
          ),
          // Fix round 1, F4: a bare SafeArea here was a non-Positioned
          // child of a StackFit.expand Stack, which stretched it to
          // the FULL screen height; StoryProgressBars' Row (only 3dp
          // tall) then centred itself inside that stretched box,
          // landing at screen mid-height instead of "across the top"
          // (spec §5.2's first sentence). Positioned pins this to the
          // top edge instead, so SafeArea only insets the notch/status
          // bar and the bars themselves stay flush with the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                child: StoryProgressBars(
                  itemCount: items.length,
                  currentIndex: index,
                  currentProgress: progress,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Semantics(
                label: 'Close story',
                button: true,
                child: IconButton(
                  iconSize: 28,
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: onDismiss,
                ),
              ),
            ),
          ),
          if (onDelete != null)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Semantics(
                  label: 'Delete this story',
                  button: true,
                  child: IconButton(
                    key: const ValueKey('story-reel-delete'),
                    iconSize: 24,
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                    onPressed: onDelete,
                  ),
                ),
              ),
            ),
          if (canReply)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: _ReplyComposer(
                  controller: replyController!,
                  focusNode: replyFocusNode!,
                  sending: sendingReply,
                  onSend: onSendReply!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Task 6 (spec §5.4): the reply-composing strip pinned above the bottom
/// safe area, visible only when [_ReelBody.canReply] is true. A single
/// text field + send button — no swipe-to-reply, no long-press menu,
/// nothing chat's own composer has, because this screen sends exactly
/// one thing (a fresh text reply quoting the current item) and nothing
/// else.
class _ReplyComposer extends StatelessWidget {
  const _ReplyComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                key: const ValueKey('story-reel-reply-field'),
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: sending ? null : (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Reply to story...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Send reply',
            button: true,
            child: IconButton(
              key: const ValueKey('story-reel-reply-send'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: sending ? null : onSend,
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolves the reel's whole gesture set from ONE [GestureDetector]
/// (spec §5.2: tap right advances, tap left goes back, hold pauses,
/// swipe down dismisses):
///
///  - `onTapDown` starts [holdThreshold]; if it fires before the
///    pointer is released/cancelled, the press is a HOLD — [onHoldStart]
///    fires and playback pauses.
///  - `onTapUp` before the timer fires is a TAP: [onTapLeft]/[onTapRight]
///    based on which half of the widget's width the pointer landed in.
///    `onTapUp` after the timer fired is the release of a hold:
///    [onHoldEnd] fires (resume) instead of navigating — a hold must
///    never also count as a nav tap.
///  - `onTapCancel` (the gesture arena decided this pointer belongs to
///    something else, e.g. a drag) always releases a hold in progress,
///    so a hold can never survive past its own pointer.
///  - `onVerticalDragUpdate`/`onVerticalDragEnd` with a net downward
///    move past [_dismissThreshold] calls [onDismiss].
class _GestureLayer extends StatefulWidget {
  const _GestureLayer({
    required this.holdThreshold,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onDismiss,
    required this.child,
  });

  final Duration holdThreshold;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  State<_GestureLayer> createState() => _GestureLayerState();
}

class _GestureLayerState extends State<_GestureLayer> {
  Timer? _holdTimer;
  bool _holding = false;
  double _dragExtent = 0;

  // A confident downward swipe, not an accidental wobble while holding.
  static const _dismissThreshold = 80.0;

  void _onTapDown(TapDownDetails details) {
    _holdTimer?.cancel();
    _holdTimer = Timer(widget.holdThreshold, () {
      _holding = true;
      widget.onHoldStart();
    });
  }

  void _onTapUp(TapUpDetails details, double width) {
    final wasHolding = _holding;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (wasHolding) {
      _holding = false;
      widget.onHoldEnd();
      return;
    }
    if (details.localPosition.dx < width / 2) {
      widget.onTapLeft();
    } else {
      widget.onTapRight();
    }
  }

  void _onTapCancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_holding) {
      _holding = false;
      widget.onHoldEnd();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Semantics(
          // Fix round 1, F8: the raw GestureDetector below carries tap
          // position and press-duration semantics that only a sighted/
          // touch user can perform — a screen-reader user has no way to
          // "tap the right half" or "hold for 200ms". This node gives
          // TalkBack/VoiceOver an explicit, discoverable action for
          // each: swipe-up/right (onIncrease) advances, swipe-down/left
          // (onDecrease) goes back — the platform convention for a
          // paged/carousel control — a long-press gesture pauses, and
          // the platform's own dismiss gesture closes the reel. Without
          // this the reel's ENTIRE primary navigation was unreachable
          // for a screen-reader user; only the close button and the
          // "Story N of M" label on the progress bars were exposed.
          container: true,
          label: 'Story viewer',
          hint:
              'Swipe up or right for the next story, swipe down or left '
              'for the previous one, double-tap and hold to pause',
          onIncrease: widget.onTapRight,
          onDecrease: widget.onTapLeft,
          onLongPress: () {
            widget.onHoldStart();
            widget.onHoldEnd();
          },
          onDismiss: widget.onDismiss,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _onTapDown,
            onTapUp: (details) => _onTapUp(details, constraints.maxWidth),
            onTapCancel: _onTapCancel,
            onVerticalDragUpdate: (details) {
              _dragExtent += details.delta.dy;
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_dragExtent > _dismissThreshold || velocity > 600) {
                widget.onDismiss();
              }
              _dragExtent = 0;
            },
            child: widget.child,
          ),
        );
      },
    );
  }
}

class _MediaView extends StatelessWidget {
  const _MediaView({
    required this.item,
    required this.player,
    required this.signedUrl,
  });

  final StoryItem item;
  final StoryItemPlayer? player;

  /// The URL `_startItemAsync` already minted for THIS item via
  /// `StoryReadGateway.signMediaUrl` — passed down rather than re-
  /// fetched here.
  ///
  /// Fix round 1, F5: this widget used to independently
  /// `ref.watch(storyMediaSignedUrlProvider(item.mediaKey))`, which
  /// minted a SECOND signed URL for every image item — one wasted
  /// `create_signed_url` round-trip per image, and worse, a second
  /// source of truth that could disagree with the first: the URL that
  /// gated `_rendered`/`markViewed` (the one `_startItemAsync` minted)
  /// was not necessarily the URL actually rendered here, so a view
  /// could be marked while the viewer was looking at `_ErrorGlyph`. This
  /// widget now renders whatever URL the screen already confirmed
  /// non-null before marking anything — one mint per item, one source
  /// of truth. Still "minted per request, never cached" (spec §5.5):
  /// `_startItemAsync` mints fresh on every item start and this widget
  /// never persists it past that item's lifetime.
  final String? signedUrl;

  @override
  Widget build(BuildContext context) {
    if (item.mediaType == 'video') {
      // The real player owns its own texture/rendering when backed by a
      // VideoPlayerController; a fake test player has nothing visual to
      // present, so this just reflects "a video is active" without
      // assuming a concrete widget type is available from the seam.
      if (player is VideoControllerStoryItemPlayer) {
        final controller = (player as VideoControllerStoryItemPlayer)
            .controller;
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 1
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        );
      }
      return const ColoredBox(color: Colors.black);
    }

    final url = signedUrl;
    if (url == null) return const _ErrorGlyph();
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const _ErrorGlyph(),
    );
  }
}

class _ErrorGlyph extends StatelessWidget {
  const _ErrorGlyph();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.broken_image_outlined, color: Colors.white54);
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(
          child: Text(
            'No stories to show.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: onClose,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(
          child: Text(
            "Couldn't load this story.",
            style: TextStyle(color: Colors.white70),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: onClose,
            ),
          ),
        ),
      ],
    );
  }
}
