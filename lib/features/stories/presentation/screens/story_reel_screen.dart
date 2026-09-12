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

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  const StoryReelScreen({
    super.key,
    required this.relationshipId,
    required this.authorId,
    this.isOwnReel = false,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
  });

  final String relationshipId;
  final String authorId;

  /// True when [authorId] is the caller's own id. `mark_story_viewed`
  /// refuses the author (spec §5.2: "the author's own preview" does not
  /// count), so this screen never even attempts the call for its own
  /// reel — see [_maybeMarkViewed].
  final bool isOwnReel;

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

  bool _paused = false;
  bool _loadingItem = false;

  /// Set once the current item has actually rendered — an image after
  /// its bytes resolve, a video after [StoryItemPlayer.initialize]
  /// succeeds. [_maybeMarkViewed] is a no-op until this is true (spec
  /// §5.2: "after a partner's active item renders successfully" — never
  /// on open, never on a failed load).
  bool _rendered = false;

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

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _setForeground(true),
      onPause: () => _setForeground(false),
      onInactive: () => _setForeground(false),
      onHide: () => _setForeground(false),
    );
  }

  void _setForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (!foreground) {
      // Backgrounding mid-item PAUSES rather than skips (spec/brief):
      // the timer/player simply stops advancing; nothing advances the
      // index, and nothing is lost.
      _setPaused(true);
    }
    // Coming back to the foreground does NOT auto-resume — same posture
    // as a hold: the viewer released their own hold explicitly, and a
    // backgrounded pause should require the same explicit tap-to-resume
    // so a story never silently races ahead while the user was looking
    // at another app.
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
      _paused = false;
      _currentDuration = kStoryImageHoldDuration;
    });

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
        unawaited(_advance(items));
      });

      setState(() {
        _loadingItem = false;
        _rendered = true;
        _currentDuration = player.duration;
      });
      player.play();
      _startTicker(generation, items);
      unawaited(_maybeMarkViewed(item));
    } else {
      // Image: no controller, no natural duration. Hold for
      // widget.imageHoldDuration on a plain Timer (spec §5.2).
      setState(() {
        _loadingItem = false;
        _rendered = true;
        _currentDuration = widget.imageHoldDuration;
      });
      _startTicker(generation, items);
      unawaited(_maybeMarkViewed(item));
    }
  }

  StoryItemPlayer _defaultVideoPlayerFactory(Uri uri) =>
      VideoControllerStoryItemPlayer(uri);

  void _startTicker(int generation, List<StoryItem> items) {
    _tickTimer?.cancel();
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
        // here too, since _advance is idempotent per generation.
        setState(() => _elapsed = _currentDuration);
        if (player == null) unawaited(_advance(items));
        return;
      }

      setState(() => _elapsed = elapsed);
    });
  }

  void _setPaused(bool paused) {
    if (_paused == paused) return;
    setState(() => _paused = paused);
    final player = _player;
    if (player == null) return;
    if (paused) {
      player.pause();
    } else {
      player.play();
    }
  }

  Future<void> _maybeMarkViewed(StoryItem item) async {
    // Never for the author's own reel (mark_story_viewed refuses the
    // author server-side, spec §5.2/§3.4) and never twice for the same
    // item.
    if (widget.isOwnReel) return;
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

  Future<void> _advance(List<StoryItem> items) async {
    if (_index + 1 < items.length) {
      _startItem(items, _index + 1);
    } else {
      _close();
    }
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

  @override
  void dispose() {
    _generation++;
    _tickTimer?.cancel();
    unawaited(_endedSub?.cancel());
    unawaited(_player?.dispose());
    _lifecycleListener?.dispose();
    super.dispose();
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
    final key = StoryReelKey(
      relationshipId: widget.relationshipId,
      authorId: widget.authorId,
    );
    final pagesAsync = ref.watch(storyReelPagesProvider(key));

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
          return _ReelBody(
            items: items,
            index: clampedIndex,
            progress: _progressFraction,
            loading: _loadingItem,
            player: _player,
            onTapLeft: () => _retreat(items),
            onTapRight: () => unawaited(_advance(items)),
            onHoldStart: () => _setPaused(true),
            onHoldEnd: () => _setPaused(false),
            onDismiss: _close,
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
    required this.onTapLeft,
    required this.onTapRight,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onDismiss,
  });

  final List<StoryItem> items;
  final int index;
  final double progress;
  final bool loading;
  final StoryItemPlayer? player;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onDismiss;

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
                : _MediaView(item: item, player: player),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: StoryProgressBars(
                itemCount: items.length,
                currentIndex: index,
                currentProgress: progress,
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
        return GestureDetector(
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
        );
      },
    );
  }
}

class _MediaView extends ConsumerWidget {
  const _MediaView({required this.item, required this.player});

  final StoryItem item;
  final StoryItemPlayer? player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final signedUrlAsync = ref.watch(
      storyMediaSignedUrlProvider(item.mediaKey),
    );
    return signedUrlAsync.when(
      data: (url) => url == null
          ? const _ErrorGlyph()
          : Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _ErrorGlyph(),
            ),
      loading: () => const CircularProgressIndicator(color: Colors.white),
      error: (_, __) => const _ErrorGlyph(),
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
