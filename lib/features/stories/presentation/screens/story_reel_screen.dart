/// The reel — the full-screen story viewer (Plan C, Task 4; spec §5.2).
///
/// **A new module.** The streak viewer
/// (`lib/features/chat/presentation/screens/streak_viewer_screen.dart`)
/// is a single-item video player whose only gesture is
/// `onTap: () => _finish()` — no segments, no navigation, no pause, no
/// dismissal gesture, no image branch (spec §5.2's own table). This
/// screen is NOT an adaptation of it: it is new code that reuses only
/// two things by pattern, not by import — signed-media loading (a
/// storage KEY is signed when first shown on this screen and reused for up
/// to 540 s on this screen only, §4.1 as amended, Wave 1) and
/// `VideoPlayerController`
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

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart'
    show chatRepositoryProvider;
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show partnerNameProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/data/story_signed_url_cache.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/widgets/story_progress_bars.dart';
import 'package:attune/features/stories/presentation/widgets/story_reel_header.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, SemanticsService;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
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

/// How long the reel reuses a signed URL it minted itself: comfortably
/// inside the 600 s TTL, so §4.5's deletion bound is unchanged.
const Duration kStorySignedUrlReuse = kStoryUrlReuseWindow;

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

/// Health signals a [StoryItemPlayer] may offer. Kept apart from
/// [StoryItemPlayer] so players that only implement the core seam (the
/// existing test fakes) keep compiling.
abstract interface class StoryItemPlayerStatus {
  /// Fires when playback fails after it started (a dropped connection, a
  /// signed URL that expired during a long pause).
  Stream<Object> get onError;

  /// True while playback waits for data.
  bool get isBuffering;
}

/// A video that is not ready by now counts as failed (02 #15).
const Duration kStoryVideoInitTimeout = Duration(seconds: 15);

/// Automatic retries for an item that failed, 1 s, 2 s then 4 s apart; the
/// person can always tap Retry or Next (02 #5).
const int kStoryItemAutoRetries = 3;

/// How many further pages the reel reads looking for where to start
/// ([StoryReelScreen.initialStoryItemId], or the first unseen story).
const int kStoryStartSearchMaxPages = 10;

/// The longest the reel waits, in all, for later pages while it looks for
/// where to start (batch-5 review, Minor 1). Then it starts at the oldest,
/// so a stalled network never leaves the person on a spinner.
const kStoryStartSearchBudget = Duration(seconds: 3);

/// A story reply that has not been answered by now counts as failed and can
/// be retried with the same message id (02 #17).
const Duration kStoryReplySendTimeout = Duration(seconds: 30);

/// Production [StoryItemPlayer]: wraps a real `VideoPlayerController`,
/// constructed and disposed the same way the streak viewer does
/// (`VideoPlayerController.networkUrl` + `initialize()` + a listener that
/// latches on end-of-clip so it cannot fire twice — mirrored from
/// `streak_viewer_screen.dart`'s own `_playAt`).
class VideoControllerStoryItemPlayer
    implements StoryItemPlayer, StoryItemPlayerStatus {
  VideoControllerStoryItemPlayer(Uri uri)
    : _controller = VideoPlayerController.networkUrl(uri);

  final VideoPlayerController _controller;
  final _endedController = StreamController<void>.broadcast();
  bool _ended = false;
  final _errorController = StreamController<Object>.broadcast();
  bool _errored = false;

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
    final value = _controller.value;
    if (value.hasError && !_errored) {
      _errored = true;
      if (!_errorController.isClosed) {
        _errorController.add(value.errorDescription ?? 'playback error');
      }
      return;
    }
    if (_ended) return;
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
  Stream<Object> get onError => _errorController.stream;

  @override
  bool get isBuffering => _controller.value.isBuffering;

  @override
  Future<void> dispose() async {
    _controller.removeListener(_onTick);
    await _endedController.close();
    await _errorController.close();
    await _controller.dispose();
  }
}

/// Why the reel is paused. Each cause sets and clears only itself, so one
/// ending (a hold released, the app back in front) never resumes a story
/// another cause still holds (02 #12; the F1 lesson generalised).
enum _PauseCause { hold, lifecycle, composer, modal, accessibility }

/// Where the current item is: loading its media, on screen, or failed.
/// "Ready" means a decoded first frame for a photo, or an initialized
/// player for a video, and is the only state that starts the clock and
/// records a view (spec §5.2; 07a V6).
enum _ItemPhase { loading, ready, failed }

/// The reel (spec §5.2). Where it opens (owner ruling 3, §5.5 as amended):
/// the partner's active reel, and the partner's ring on a calendar day
/// ([StoryReelScreen.forDay] with [dayAuthorId], 04 #4), at the first story
/// the viewer has not seen (the oldest when all are seen); a reply's quoted
/// story via [initialStoryItemId]; otherwise the oldest, as on my own day
/// ring. Watched segments are faded,
/// not skipped ([StoryProgressBars.viewed]).
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
    this.imageProviderBuilder,
  }) : occurredOn = null,
       placeItems = null,
       initialStoryItemId = null,
       dayAuthorId = null;

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
    this.initialStoryItemId,
    this.dayAuthorId,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
    this.imageProviderBuilder,
  }) : authorId = '',
       isOwnReel = false,
       placeItems = null;

  /// Places mode (couple map, spec §3.3): the stories behind a map pin or
  /// cluster, oldest first, as a fixed list — no pager. Per-item author
  /// checks, like day mode. Adds "Remove from map" for the author.
  const StoryReelScreen.forPlaces({
    super.key,
    required this.relationshipId,
    required List<StoryItem> items,
    this.videoPlayerFactory,
    this.imageHoldDuration = kStoryImageHoldDuration,
    this.imageProviderBuilder,
  }) : placeItems = items,
       authorId = '',
       isOwnReel = false,
       occurredOn = null,
       initialStoryItemId = null,
       dayAuthorId = null;

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

  /// Non-null selects places mode (see [StoryReelScreen.forPlaces]).
  final List<StoryItem>? placeItems;

  /// Day mode: the story to start at (a story reply's quoted item, 02 #11).
  /// Pages forward until found; falls back to the first item.
  final String? initialStoryItemId;

  /// Day mode for one author's ring on the calendar (04 #4): only that
  /// author's stories play. Null plays the whole day. The server reads them
  /// (Wave 5, `p_author_id`); the filter here stays for an older server.
  final String? dayAuthorId;

  /// Test seam: mints a [StoryItemPlayer] for a video item's signed URL.
  /// Defaults to [VideoControllerStoryItemPlayer]. See this file's header.
  final StoryItemPlayer Function(Uri uri)? videoPlayerFactory;

  /// Test seam so the 5-second image hold can be asserted against a
  /// smaller number without weakening what production uses (which stays
  /// at [kStoryImageHoldDuration] by default).
  final Duration imageHoldDuration;

  /// Test seam, as on [StreakViewerScreen]: how a signed photo URL becomes
  /// an [ImageProvider]. Production uses [NetworkImage].
  final ImageProvider Function(String url)? imageProviderBuilder;

  @override
  ConsumerState<StoryReelScreen> createState() => _StoryReelScreenState();
}

class _StoryReelScreenState extends ConsumerState<StoryReelScreen> {
  int _index = 0;

  /// The story on screen. Delete, Reply, the bars and auto-advance act on
  /// this item, found by id in the live list, never by position: the list
  /// is refetched underneath the reel (review 02 #1/#4, 07a group A).
  StoryItem? _current;

  /// Playback starts once, from the first non-empty list. Replaces the old
  /// render-state heuristic that restarted a failed first item every frame
  /// (review 02 #5).
  bool _started = false;

  /// Stories this screen deleted: hidden at once, so the reel steps off
  /// them before, or without, the refetch that confirms it (02 #1).
  final Set<String> _removedIds = {};

  /// A Delete or Remove-from-map call is in flight: both buttons are
  /// disabled, and the reel stays paused ([_PauseCause.modal]) until it
  /// returns (final review #2).
  bool _deleting = false;

  /// Latched by [_close]: the reel pops itself once, and only itself.
  bool _closing = false;

  /// Latched while the reel waits for the next page at the end of the
  /// loaded one; [_pageLoading] shows its spinner.
  bool _advancingPage = false;
  bool _pageLoading = false;

  /// One author's day ring paging forward to that author's first story
  /// ([_fillAuthorPage]): started once, then done.
  bool _authorFillStarted = false;
  bool _authorFillDone = false;

  /// One author's ring on a busy day: their stories may start pages in.
  /// Pages forward once, at most [kStoryStartSearchMaxPages], then lets the
  /// empty state speak if there are still none.
  void _fillAuthorPage() {
    if (_authorFillStarted) return;
    _authorFillStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var page = 0; page < kStoryStartSearchMaxPages; page++) {
          if (!mounted || _liveItems().isNotEmpty || !_pagerHasMore()) break;
          await _pagerLoadMore();
          // A failed page (the pager keeps its list and reports the error)
          // ends the run: the empty branch then offers Retry instead of
          // re-fetching it back to back (M-1). A loadMore that only waited
          // out a refresh fetched nothing, so the loop goes round again.
          if (!mounted || _pagerHasError()) break;
        }
      } catch (_) {
        // A failed page leaves the empty state to say there is nothing.
      } finally {
        _authorFillDone = true;
        if (mounted) setState(() {});
      }
    });
  }

  /// Retry after a failed author fill: page forward again (M-1).
  void _retryAuthorFill() {
    setState(() {
      _authorFillStarted = false;
      _authorFillDone = false;
    });
  }

  /// I-1: a refresh restarts the day at page one, and one author's ring may
  /// have its story on screen pages past it. While the reel pages forward
  /// to that story, it keeps drawing the list it last showed.
  List<StoryItem>? _seekHold;
  Future<void>? _seekDone;

  /// The visible list [_buildLoaded] last drew.
  List<StoryItem> _shownItems = const [];

  /// Final review M-1: one author's day ring, after deleting the last of
  /// their loaded stories, pages forward for their next one; a spinner
  /// stands in for the deleted story meanwhile.
  bool _pagingPastDeleted = false;

  /// Whether [items] holds a story posted after [current] (lists are
  /// oldest-first by `(created_at, id)`).
  static bool _hasNewer(List<StoryItem> items, StoryItem current) =>
      items.any(
        (i) =>
            i.createdAt.isAfter(current.createdAt) ||
            (i.createdAt == current.createdAt &&
                i.id.compareTo(current.id) > 0),
      );

  /// Pages forward, at most [kStoryStartSearchMaxPages], for the deleted
  /// [gone]'s author's next story, then plays it; with none, the newest one
  /// left before it, and closes only when none remain (M-1). A loadMore
  /// that only waited out the delete's refresh fetched nothing, so the
  /// loop goes round again, as [_advanceAtEndOfPage] does.
  void _pagePastDeleted(StoryItem gone) {
    setState(() => _pagingPastDeleted = true);
    unawaited(() async {
      try {
        for (var page = 0; page < kStoryStartSearchMaxPages; page++) {
          if (!mounted || !_pagerHasMore()) break;
          await _pagerLoadMore();
          if (!mounted || _pagerHasError()) break;
          if (_hasNewer(_liveItems(), gone)) break;
        }
      } catch (_) {
        // Settled below on whatever is loaded.
      } finally {
        if (mounted) {
          setState(() => _pagingPastDeleted = false);
          final items = _liveItems();
          if (items.isEmpty) {
            _close();
          } else {
            _startItem(items, _successorIndex(items, gone));
          }
        }
      }
    }());
  }

  /// The story on screen may still be on a page not loaded since the last
  /// refresh: one author's day ring, more pages, and the story newer than
  /// the last loaded row (lists are oldest-first by `(created_at, id)`).
  bool _mayLieAhead(StoryItem current) {
    if (widget.dayAuthorId == null || _removedIds.contains(current.id)) {
      return false;
    }
    if (!_pagerHasMore()) return false;
    final raw = _pagerCurrentItems();
    if (raw == null || raw.isEmpty) return true;
    final last = raw.last;
    return current.createdAt.isAfter(last.createdAt) ||
        (current.createdAt == last.createdAt &&
            current.id.compareTo(last.id) > 0);
  }

  /// Pages forward, at most [kStoryStartSearchMaxPages], until the story on
  /// screen is loaded again, then reconciles by id. A failed page, or no
  /// more pages, reconciles on what is loaded (successor, or close).
  void _seekCurrent(StoryItem current) {
    setState(() => _seekHold = _shownItems.isEmpty ? [current] : _shownItems);
    final done = Completer<void>();
    _seekDone = done.future;
    unawaited(() async {
      try {
        for (var page = 0; page < kStoryStartSearchMaxPages; page++) {
          // The story on screen now: a delete during the seek stepped on
          // to the next one in the held list.
          if (!mounted || !_mayLieAhead(_current ?? current)) break;
          // Started from inside the refresh's update: the first loadMore
          // waits it out and fetches nothing, so the loop goes round again.
          await _pagerLoadMore();
          if (!mounted || _pagerHasError()) break;
        }
      } catch (_) {
        // Reconciled below on whatever is loaded.
      } finally {
        _seekDone = null;
        done.complete();
        if (mounted) {
          setState(() => _seekHold = null);
          final now = _current;
          if (now != null) _reconcile(_liveItems(), now);
        }
      }
    }());
  }

  /// The start search's overall budget ([kStoryStartSearchBudget]).
  Timer? _startSearchTimer;

  /// The reel's own dialog while one is open ([_showReelDialog]), set
  /// before it is pushed, so [_close] can dismiss it first.
  DialogRoute<Object?>? _dialogRoute;

  /// [_close] was asked for while a dialog was open; it runs once the
  /// dialog is down.
  bool _closeAfterDialog = false;

  List<StoryItem> _visible(List<StoryItem> raw) {
    final author = widget.dayAuthorId;
    if (_removedIds.isEmpty && author == null) return raw;
    return raw
        .where(
          (i) =>
              !_removedIds.contains(i.id) &&
              (author == null || i.authorId == author),
        )
        .toList();
  }

  /// This screen's day pager key: one author's stories when opened from a
  /// calendar ring (Wave 5 asks the server for them), else the whole day.
  StoryDayKey get _dayKey => StoryDayKey(
    relationshipId: widget.relationshipId,
    occurredOn: widget.occurredOn!,
    authorId: widget.dayAuthorId,
  );

  /// Places mode's own copy of the list, so removals take effect at once.
  late final List<StoryItem> _placeItems = [...?widget.placeItems];
  bool get _placesMode => widget.placeItems != null;
  Timer? _tickTimer;
  StoryItemPlayer? _player;
  StreamSubscription<void>? _endedSub;

  /// Automatic retries spent on the current item ([kStoryItemAutoRetries]).
  int _autoRetries = 0;
  Timer? _retryTimer;

  /// The video init deadline ([kStoryVideoInitTimeout]); screen-owned, so a
  /// disposed reel leaves no pending timer.
  Timer? _initTimer;

  /// A video still initializing: disposed by [_stopMedia] if the reel moves
  /// on before it is ready.
  StoryItemPlayer? _pendingPlayer;
  StreamSubscription<Object>? _errorSub;

  /// Elapsed time within the current item, advanced by [_tickTimer] for
  /// an image and read from the player for a video. Drives
  /// [StoryProgressBars.currentProgress].
  Duration _elapsed = Duration.zero;
  Duration _currentDuration = kStoryImageHoldDuration;

  /// The player's buffering state as of the last tick. A flip repaints
  /// even under reduce motion, which otherwise skips mid-item repaints and
  /// would never show (or clear) the buffering spinner (batch-3 review #1).
  bool _buffering = false;

  final Set<_PauseCause> _pauseCauses = {};
  bool get _paused => _pauseCauses.isNotEmpty;

  /// The reply this person is typing goes to the story they started it on.
  StoryItem? _replyTarget;

  /// The current item's load phase. [_ItemPhase.ready] is reached only
  /// once the item has actually rendered — an image after its first frame
  /// decodes, a video after [StoryItemPlayer.initialize] succeeds — and
  /// only then do its clock and [_maybeMarkViewed] run (spec §5.2: "after
  /// a partner's active item renders successfully" — never on open, never
  /// on a failed load).
  _ItemPhase _phase = _ItemPhase.loading;

  /// The provider [_loadImage] resolved for the current photo: the same
  /// object that gated ready is the one rendered. Fix round 1, F5:
  /// previously `_MediaView` minted its OWN second URL, risking
  /// disagreement between "what gated the render/mark check" and "what
  /// was actually rendered." Reset to null on every item change so the
  /// previous item is never shown while the next one loads.
  ImageProvider? _currentImage;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  /// Guards a single `mark_story_viewed` call per item id, the same
  /// shape as the streak viewer's `_viewSpent` guard for its own
  /// once-only server call.
  final Set<String> _markedItemIds = {};

  /// Signed URLs minted on THIS screen, by storage key, reused while
  /// younger than [kStorySignedUrlReuse] (STORIES.md §4.1 as amended):
  /// the preloaded photo is the one displayed, and a step back does not
  /// re-sign. Never stored beyond this screen. Keyed by storage key, so an
  /// archive swap (a new key) always signs afresh.
  final Map<String, ({String url, DateTime mintedAt})> _signedUrls = {};

  Future<String?> _signedUrlFor(StoryItem item) async {
    final cached = _signedUrls[item.mediaKey];
    // Same age rule as the rings' cache: the injected clock, a negative age
    // (clock set back) is stale, aged from the request's start.
    if (cached != null && storyUrlFreshFor(cached.mintedAt) != null) {
      return cached.url;
    }
    final startedAt = clock.now();
    final url = await ref
        .read(storyReadGatewayProvider)
        .signMediaUrl(item.mediaKey);
    if (url != null) {
      _signedUrls[item.mediaKey] = (url: url, mintedAt: startedAt);
    }
    return url;
  }

  /// Bumped on every item change/dispose so a callback from an item the
  /// user has since left (advanced past, backgrounded across, or that
  /// this screen has been popped from) cannot mutate current state —
  /// this task's own "guard every post-await state write" requirement,
  /// following Task 2's F1/F2 lesson.
  int _generation = 0;

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

  /// One client message id per composed reply: kept while the same text
  /// goes to the same story ([_replyDraftKey] is `'$storyItemId|$text'`).
  String? _replyDraftId;
  String? _replyDraftKey;

  @override
  void initState() {
    super.initState();
    // Stories Wave 3: the shell keeps this route mounted behind the privacy
    // cover and the Safety lock check, so "foreground" is whether Attune's
    // content is on screen (resumed AND the lock open), not the lifecycle
    // alone: a return that ends at the PIN screen must not play.
    ref.listenManual<bool>(
      appContentVisibleProvider,
      (_, visible) => _setForeground(visible),
    );
    // Opened while not on screen (a notification tapped behind the cover):
    // start paused. No setState in initState; the first build reads it.
    if (!ref.read(appContentVisibleProvider)) {
      _appForeground = false;
      _pauseCauses.add(_PauseCause.lifecycle);
    }
    // Composing a reply pauses the reel on its own cause — the item must
    // not advance out from under a partially-typed reply, and releasing a
    // hold must not resume it (02 #12).
    _replyFocusNode.addListener(() {
      if (!mounted) return;
      final focused = _replyFocusNode.hasFocus;
      _replyTarget = focused ? _current : null;
      _setPaused(_PauseCause.composer, focused);
    });
    if (!_placesMode) {
      ref.listenManual<AsyncValue<List<StoryItem>>>(
        _itemsProvider(),
        (_, next) => _onItemsChanged(
          next.valueOrNull == null ? null : _visible(next.valueOrNull!),
        ),
      );
    }
  }

  void _setForeground(bool foreground) {
    if (_appForeground == foreground) return;
    _appForeground = foreground;
    if (!foreground) {
      // Backgrounding mid-item PAUSES rather than skips (spec/brief):
      // the timer/player simply stops advancing; nothing advances the
      // index, and nothing is lost.
      _setPaused(_PauseCause.lifecycle, true);
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
      // to long-press. Clearing only the lifecycle cause here leaves any
      // other cause (a hold, the composer) in control — see
      // [_PauseCause].
      _setPaused(_PauseCause.lifecycle, false);
      // Stories Wave 3: an item that finished loading while not on screen
      // counts as seen only now (once per item: [_markedItemIds]).
      final current = _current;
      if (current != null && _phase == _ItemPhase.ready) {
        unawaited(_maybeMarkViewed(current));
      }
    }
  }

  /// The pager backing this screen (author or day mode).
  ProviderListenable<AsyncValue<List<StoryItem>>> _itemsProvider() {
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return storyDayItemsProvider(_dayKey);
    }
    return storyReelPagesProvider(
      StoryReelKey(
        relationshipId: widget.relationshipId,
        authorId: widget.authorId,
      ),
    );
  }

  /// The list backing the screen right now.
  List<StoryItem> _liveItems() =>
      _visible(_pagerCurrentItems() ?? const <StoryItem>[]);

  int _currentIndexIn(List<StoryItem> items) {
    final id = _current?.id;
    return id == null ? -1 : items.indexWhere((i) => i.id == id);
  }

  /// Reconciles a refreshed list with the story on screen: same story,
  /// new position (and fresh row data); or, when it is gone, stop it and
  /// play the story that followed it, or close when nothing is left.
  void _onItemsChanged(List<StoryItem>? items) {
    final current = _current;
    if (items == null || current == null || !mounted) return;
    // Paging past a deleted story settles once it lands (M-1).
    if (_pagingPastDeleted) return;
    // A seek in flight reconciles once it lands (I-1), except that a story
    // this screen deleted steps off at once, within the held list, never
    // after the page fetch (Wave 4 carry).
    final hold = _seekHold;
    if (hold != null) {
      if (!_removedIds.contains(current.id)) return;
      final kept = [
        for (final i in hold)
          if (!_removedIds.contains(i.id)) i,
      ];
      if (kept.isEmpty) {
        setState(() => _seekHold = null);
        _reconcile(items, current);
        return;
      }
      setState(() => _seekHold = kept);
      _reconcile(kept, current);
      return;
    }
    if (!items.any((i) => i.id == current.id) && _mayLieAhead(current)) {
      _seekCurrent(current);
      return;
    }
    _reconcile(items, current);
  }

  /// [_onItemsChanged] once the story on screen is known not to lie on a
  /// page still to load.
  void _reconcile(List<StoryItem> items, StoryItem current) {
    final target = _replyTarget;
    if (target != null && !items.any((i) => i.id == target.id)) {
      _onReplyTargetGone();
    }
    final at = items.indexWhere((i) => i.id == current.id);
    if (at >= 0) {
      setState(() {
        _index = at;
        _current = items[at];
      });
      return;
    }
    _stopMedia();
    // M-1: the deleted story ended this author's loaded run, and the day
    // has more pages: their next story may be on one. Not during a seek,
    // which reconciles once its page lands.
    if (widget.dayAuthorId != null &&
        _removedIds.contains(current.id) &&
        _seekDone == null &&
        !_hasNewer(items, current) &&
        _pagerHasMore()) {
      _pagePastDeleted(current);
      return;
    }
    if (items.isEmpty) {
      _close();
      return;
    }
    _startItem(items, _successorIndex(items, current));
  }

  /// The story being replied to was deleted or expired (batch-1 review,
  /// Minor 3). Close the keyboard and keep the text, so nothing goes to a
  /// story the person did not choose; a Send now quotes the story on
  /// screen. A send already in flight reports its own result instead.
  void _onReplyTargetGone() {
    _replyTarget = null;
    if (_replyFocusNode.hasFocus) _replyFocusNode.unfocus();
    if (_sendingReply || _replyController.text.trim().isEmpty) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'That story is no longer available. Your reply is still here.',
          ),
        ),
      );
  }

  /// The first story posted after [gone] (lists are oldest-first by
  /// `(created_at, id)`), else the newest one left.
  static int _successorIndex(List<StoryItem> items, StoryItem gone) {
    final at = items.indexWhere(
      (i) =>
          i.createdAt.isAfter(gone.createdAt) ||
          (i.createdAt == gone.createdAt && i.id.compareTo(gone.id) > 0),
    );
    return at == -1 ? items.length - 1 : at;
  }

  /// Stops whatever is playing without choosing what comes next. Bumps
  /// [_generation] so every late callback for it is ignored.
  void _stopMedia() {
    _generation++;
    _tickTimer?.cancel();
    _tickTimer = null;
    unawaited(_endedSub?.cancel());
    _endedSub = null;
    final player = _player;
    _player = null;
    if (player != null) {
      player.pause();
      unawaited(player.dispose());
    }
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _initTimer?.cancel();
    _initTimer = null;
    unawaited(_errorSub?.cancel());
    _errorSub = null;
    final pending = _pendingPlayer;
    _pendingPlayer = null;
    if (pending != null) unawaited(pending.dispose());
  }

  void _startItem(List<StoryItem> items, int index, {bool retry = false}) =>
      unawaited(_startItemAsync(items, index, retry: retry));

  Future<void> _startItemAsync(
    List<StoryItem> items,
    int index, {
    bool retry = false,
  }) async {
    // NOT awaited inside: this can run from INSIDE _endedSub's own onEnded
    // callback (onEnded -> _advance -> _startItem -> here); [_stopMedia]
    // cancels it fire-and-forget, since awaiting a broadcast cancel from
    // inside that same delivery deadlocks.
    _stopMedia();
    if (!retry) _autoRetries = 0;
    final generation = _generation;
    final item = items[index];
    setState(() {
      _index = index;
      _current = item;
      _elapsed = Duration.zero;
      _phase = _ItemPhase.loading;
      // A hold never carries across an item transition. The other causes
      // do (fix round 1, F1): a backgrounded app starts the next item
      // paused too.
      _pauseCauses.remove(_PauseCause.hold);
      _currentDuration = widget.imageHoldDuration;
      // Fix round 1, F5: never show the previous item's media while the
      // next one loads.
      _currentImage = null;
    });
    // Fix round 1, F8: a live announcement on every item change.
    unawaited(
      SemanticsService.announce(
        'Story ${index + 1} of ${items.length}',
        TextDirection.ltr,
      ),
    );

    final signedUrl = await _signedUrlFor(item);
    if (!mounted || generation != _generation) return;
    if (signedUrl == null) {
      _onItemFailed(generation);
      return;
    }
    if (item.mediaType == 'video') {
      await _loadVideo(item, signedUrl, generation);
    } else {
      _loadImage(item, signedUrl, generation);
    }
  }

  static ImageProvider _networkImage(String url) => NetworkImage(url);

  /// Resolves the photo itself and waits for its first decoded frame: the
  /// provider that gates ready is the one [_MediaView] renders (F5).
  void _loadImage(StoryItem item, String url, int generation) {
    final provider = (widget.imageProviderBuilder ?? _networkImage)(url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!mounted ||
            generation != _generation ||
            _phase != _ItemPhase.loading) {
          return;
        }
        _onItemReady(item, generation, widget.imageHoldDuration);
      },
      onError: (_, __) {
        if (!mounted || generation != _generation) return;
        _onItemFailed(generation);
      },
    );
    setState(() => _currentImage = provider);
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  Future<void> _loadVideo(StoryItem item, String url, int generation) async {
    final player = (widget.videoPlayerFactory ?? _defaultVideoPlayerFactory)(
      Uri.parse(url),
    );
    _pendingPlayer = player;
    final ready = Completer<bool>();
    final initTimer = Timer(kStoryVideoInitTimeout, () {
      if (!ready.isCompleted) ready.complete(false);
    });
    _initTimer = initTimer;
    unawaited(
      player.initialize().then(
        (_) {
          if (!ready.isCompleted) ready.complete(true);
        },
        onError: (Object _) {
          if (!ready.isCompleted) ready.complete(false);
        },
      ),
    );
    final ok = await ready.future;
    // Only this load's own deadline: a stale init settling late must not
    // cancel the next video's (final review #3).
    initTimer.cancel();
    if (identical(_initTimer, initTimer)) _initTimer = null;
    final stillMine = identical(_pendingPlayer, player);
    if (stillMine) _pendingPlayer = null;
    if (!mounted || generation != _generation || !ok) {
      if (stillMine) await player.dispose();
      if (mounted && generation == _generation && !ok) {
        _onItemFailed(generation);
      }
      return;
    }
    _player = player;
    _endedSub = player.onEnded.listen((_) {
      if (!mounted || generation != _generation) return;
      unawaited(_advance(generation));
    });
    if (player is StoryItemPlayerStatus) {
      _errorSub = (player as StoryItemPlayerStatus).onError.listen((_) {
        if (!mounted || generation != _generation) return;
        _tickTimer?.cancel();
        _tickTimer = null;
        _player?.pause();
        _onItemFailed(generation);
      });
    }
    _onItemReady(item, generation, player.duration);
    // Only start playback if nothing is pausing the reel (fix round 1,
    // F1): a video that became ready while backgrounded stays paused.
    if (!_paused) player.play();
  }

  /// The item is on screen: only now does its clock run and its view count.
  void _onItemReady(StoryItem item, int generation, Duration duration) {
    setState(() {
      _phase = _ItemPhase.ready;
      _currentDuration = duration;
    });
    _startTicker(generation);
    // Stories Wave 3: rendered behind the privacy cover or the Safety lock
    // check is not seen; [_setForeground] marks it once Attune is back.
    if (_appForeground) unawaited(_maybeMarkViewed(item));
    // Fix round 1, F6 (spec §5.2 "next-item preloading"): warm the next
    // photo once this one is up.
    final live = _liveItems();
    final at = _currentIndexIn(live);
    if (at >= 0) _preloadNextItem(live, at);
  }

  /// The item cannot be shown. Say so, offer Retry and Next, and retry on
  /// a growing gap a bounded number of times; never in a loop (02 #5).
  void _onItemFailed(int generation) {
    final key = _current?.mediaKey;
    if (key != null) _signedUrls.remove(key);
    setState(() => _phase = _ItemPhase.failed);
    if (_autoRetries >= kStoryItemAutoRetries) return;
    final delay = Duration(seconds: 1 << _autoRetries);
    _autoRetries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted || generation != _generation) return;
      _retryCurrent();
    });
  }

  /// Reloads the story on screen from the live list (so a swapped storage
  /// key is the one signed). A manual Retry earns a fresh set of retries.
  void _retryCurrent({bool manual = false}) {
    if (manual) _autoRetries = 0;
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at < 0) return;
    _startItem(items, at, retry: true);
  }

  /// Best-effort warm-up for `items[index + 1]`, if it exists and is an
  /// image (a video's warm-up would mean constructing and initializing
  /// a whole second [StoryItemPlayer]/[VideoPlayerController] ahead of
  /// time, which is a materially bigger change than this fix round's
  /// scope — see this task's report for that call). Failures are
  /// swallowed: this is a pure optimization, never a correctness path,
  /// so nothing here may throw into an unguarded context or affect
  /// `_phase`/`markViewed` for the CURRENT item.
  void _preloadNextItem(List<StoryItem> items, int currentIndex) {
    final nextIndex = currentIndex + 1;
    if (nextIndex >= items.length) return;
    final next = items[nextIndex];
    if (next.mediaType != 'image') return;

    unawaited(() async {
      try {
        final url = await _signedUrlFor(next);
        if (url == null || !mounted) return;
        await precacheImage(
          (widget.imageProviderBuilder ?? _networkImage)(url),
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

  void _startTicker(int generation) {
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
    _buffering = false;
    _tickTimer = Timer.periodic(kStoryProgressTickInterval, (_) {
      if (!mounted || generation != _generation || _paused) return;

      final player = _player;
      final elapsed = player != null
          ? player.position
          : _elapsed + kStoryProgressTickInterval;

      if (elapsed >= _currentDuration) {
        // One-shot (07a group C): stop this clock before advancing, so the
        // completion cannot fire again every tick while the next item (or
        // the close transition) is on its way. For a video this is also a
        // fallback when onEnded never arrives; whichever runs first wins on
        // the generation guard.
        _tickTimer?.cancel();
        _tickTimer = null;
        setState(() => _elapsed = _currentDuration);
        unawaited(_advance(generation));
        return;
      }

      final buffering =
          player is StoryItemPlayerStatus &&
          (player as StoryItemPlayerStatus).isBuffering;
      final bufferingChanged = buffering != _buffering;
      _buffering = buffering;

      if (reduceMotion && !bufferingChanged) {
        // Track time without an intermediate repaint — the segment
        // stays visually at its start-of-item state until the jump to
        // fully-filled above, rather than smoothly animating.
        _elapsed = elapsed;
      } else {
        // Under reduce motion only a buffering flip lands here: the
        // spinner must show or go. The bar steps to where it is, the same
        // discrete repaint a hold or pause already causes (no animation).
        setState(() => _elapsed = elapsed);
      }
    });
  }

  void _setPaused(_PauseCause cause, bool on) {
    final wasPaused = _paused;
    final changed = on ? _pauseCauses.add(cause) : _pauseCauses.remove(cause);
    if (!changed) return;
    setState(() {});
    _applyPausedTransition(wasPaused);
  }

  /// Screen-reader pause (02 #18): its own cause, so neither a hold release
  /// nor moving to the next story resumes it; only playing it again does.
  void _toggleAccessibilityPause() {
    final pausing = !_pauseCauses.contains(_PauseCause.accessibility);
    _setPaused(_PauseCause.accessibility, pausing);
    unawaited(
      SemanticsService.announce(
        pausing ? 'Paused' : 'Playing',
        Directionality.of(context),
      ),
    );
  }

  /// Drives the actual player/ticker effect off the COMBINED [_paused]
  /// state, only when it actually changed in [_setPaused] — e.g.
  /// backgrounding while already held-paused must not
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
    final isOwn = widget.occurredOn != null || _placesMode
        ? item.authorId == ref.read(currentUserProvider)?.id
        : widget.isOwnReel;
    if (isOwn) return;
    if (_markedItemIds.contains(item.id)) return;
    _markedItemIds.add(item.id);
    final generation = _generation;
    try {
      await ref.read(storyReadGatewayProvider).markViewed(storyItemId: item.id);
      // Spec 1a: the server bumps story_change_signals only while the couple
      // shows seen-state, so my own ring refreshes from here instead.
      if (mounted) ref.invalidate(storyRingSummaryProvider(widget.relationshipId));
      // Wave 5: a day ring's brightness comes from the month's counts, so
      // every first view (from a day, a map pin or the Conversations ring)
      // re-reads that month: the change signal does not fire while seen
      // receipts are off, and the Month view stays alive in Together.
      if (mounted && !item.hasBeenViewed) {
        ref.invalidate(
          storyDayCountsProvider(
            StoryDayRangeKey.month(
              relationshipId: widget.relationshipId,
              day: item.occurredOn,
            ),
          ),
        );
      }
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
  Future<void> _advance(int fromGeneration) async {
    if (fromGeneration != _generation) return;
    // Advance from where the story on screen really is (I-1).
    final seeking = _seekDone;
    if (seeking != null) {
      await seeking;
      if (!mounted || fromGeneration != _generation) return;
    }
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at + 1 < items.length) {
      _startItem(items, at + 1);
      return;
    }
    return _advanceAtEndOfPage(fromGeneration);
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
  Future<void> raceAdvanceForTest([List<StoryItem>? unused]) async {
    final generation = _generation;
    unawaited(_advance(generation));
    unawaited(_advance(generation));
  }

  Future<void> _advanceAtEndOfPage(int fromGeneration) async {
    // Fix round 1, F3: reaching the end of the currently-loaded PAGE is
    // not necessarily the end of the reel — list_active_story_items
    // pages at 50 (spec §5.5) and an author can post more than that in
    // 24h (spec §7: "no posting limit"). This only ever CALLS
    // `loadMore()` on whichever pager backs this screen, never
    // re-implements paging. Wave 1 (02 #13): latched, so a tap while the
    // page loads waits for it instead of reading the short list and
    // closing.
    if (_advancingPage) return;
    _advancingPage = true;
    try {
      // Two passes: a loadMore that landed during a refresh returns once the
      // refresh ends without fetching; the second pass fetches page two.
      // One author's day ring may need several pages to reach their next
      // story (04 #4); the whole day needs at most two passes.
      final passes = widget.dayAuthorId == null ? 2 : kStoryStartSearchMaxPages;
      for (var pass = 0; pass < passes; pass++) {
        if (!_pagerHasMore()) break;
        setState(() => _pageLoading = true);
        await _pagerLoadMore();
        if (!mounted || fromGeneration != _generation) return;
        final items = _liveItems();
        final at = _currentIndexIn(items);
        if (at + 1 < items.length) {
          _startItem(items, at + 1);
          return;
        }
      }
      _close();
    } finally {
      _advancingPage = false;
      if (mounted) setState(() => _pageLoading = false);
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
    if (_placesMode) return false;
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref.read(storyDayItemsProvider(_dayKey).notifier).hasMore;
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
    if (_placesMode) return Future.value();
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref.read(storyDayItemsProvider(_dayKey).notifier).loadMore();
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

  /// The pager's last read or page failed (it keeps the list it had).
  bool _pagerHasError() {
    if (_placesMode) return false;
    return ref.read(_itemsProvider()).hasError;
  }

  List<StoryItem>? _pagerCurrentItems() {
    if (_placesMode) return _placeItems;
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref.read(storyDayItemsProvider(_dayKey)).valueOrNull;
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

  /// Re-reads whichever pager backs this screen.
  Future<void> _refreshPager() {
    if (_placesMode) return Future.value();
    final occurredOn = widget.occurredOn;
    if (occurredOn != null) {
      return ref.read(storyDayItemsProvider(_dayKey).notifier).refresh();
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
        .refresh();
  }

  Future<void> _beginPlayback() async {
    final index = await _resolveStartIndex();
    if (!mounted || _current != null) return;
    final items = _liveItems();
    if (items.isEmpty) return;
    _startItem(items, index.clamp(0, items.length - 1));
  }

  /// Where playback starts (owner ruling 3; STORIES.md §5.5 as amended):
  /// the quoted story when opened from a reply; the first unseen story in
  /// the partner's active reel (the oldest when all are seen); otherwise
  /// the oldest. Pages forward, at most [kStoryStartSearchMaxPages].
  Future<int> _resolveStartIndex() async {
    final targetId = widget.initialStoryItemId;
    final myId = ref.read(currentUserProvider)?.id;
    // The partner's ring on a calendar day opens where the partner's
    // active reel would: their first story I have not seen (04 #4).
    final partnerDayRing =
        widget.occurredOn != null &&
        widget.dayAuthorId != null &&
        widget.dayAuthorId != myId;
    final firstUnseen =
        targetId == null &&
        ((widget.occurredOn == null && !_placesMode && !widget.isOwnReel) ||
            partnerDayRing);
    if (targetId == null && !firstUnseen) return 0;
    bool matches(StoryItem i) =>
        targetId != null ? i.id == targetId : !i.hasBeenViewed;
    // Started only when a later page is needed, so the usual first-page
    // match never arms a timer.
    Completer<void>? budget;
    try {
      for (var page = 0; ; page++) {
        final at = _liveItems().indexWhere(matches);
        if (at >= 0) return at;
        if (!_pagerHasMore() || page >= kStoryStartSearchMaxPages) return 0;
        if (budget == null) {
          final expired = budget = Completer<void>();
          _startSearchTimer = Timer(kStoryStartSearchBudget, expired.complete);
        }
        // A failed or overdue page ends the search at the oldest.
        final loaded = await Future.any([
          _pagerLoadMore().then((_) => true, onError: (_) => false),
          budget.future.then((_) => false),
        ]);
        if (!mounted || !loaded) return 0;
      }
    } finally {
      _startSearchTimer?.cancel();
      _startSearchTimer = null;
    }
  }

  void _retreat() {
    final items = _liveItems();
    final at = _currentIndexIn(items);
    if (at > 0) {
      _startItem(items, at - 1);
    } else if (at == 0) {
      // Reference apps restart the first story on tap-back (02 #27).
      _startItem(items, 0);
    }
  }

  /// While the reply field has focus, a tap on the story only closes the
  /// keyboard. It never pages the reel under a half-typed reply (07a §3).
  bool _consumeTapForComposer() {
    if (!_replyFocusNode.hasFocus) return false;
    _replyFocusNode.unfocus();
    return true;
  }

  void _onTapNext() {
    if (_consumeTapForComposer()) return;
    unawaited(_advance(_generation));
  }

  void _onTapBack() {
    if (_consumeTapForComposer()) return;
    _retreat();
  }

  /// Closes the reel once. Pops only when this reel's own route is on top:
  /// never a confirm dialog above it, never the screen beneath it while
  /// the reel is already animating out (07a V4).
  void _close() {
    if (_closing || !mounted) return;
    // A signal emptied the reel under one of its own dialogs (batch-1
    // review, Minor 5): dismiss that dialog, which asks about a story that
    // is gone, and close once it is down ([_showReelDialog]'s finally). The
    // dialog lives on the root navigator, which may not be the reel's, so
    // it is popped through its own route, never the reel's navigator.
    final dialog = _dialogRoute;
    if (dialog != null) {
      if (!_closeAfterDialog) {
        _closeAfterDialog = true;
        final navigator = dialog.navigator;
        if (navigator != null && dialog.isActive) {
          if (dialog.isCurrent) {
            navigator.pop();
          } else {
            // Covered by another route: remove it in place. removeRoute
            // never completes the push future, so [_showReelDialog]'s
            // finally will not run; finish the close here instead.
            navigator.removeRoute(dialog);
            _dialogRoute = null;
            _closeAfterDialog = false;
            _setPaused(_PauseCause.modal, false);
            _close();
          }
        }
      }
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _closing = true;
    _stopMedia();
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      unawaited(navigator.maybePop());
    }
  }

  /// Shows a dialog above the reel with the story paused underneath, so it
  /// cannot advance or finish behind the question (02 #14).
  ///
  /// The route is built and recorded before it is pushed, so the reel
  /// knows a dialog is open from the same frame (batch-2 review, Minor 2).
  /// Same route and defaults as [showDialog].
  ///
  /// When [keepPausedAfter] says so for the dialog's result, the modal
  /// pause outlives the dialog and the caller releases it
  /// ([_releaseActionPause]) once the action it confirmed has returned.
  Future<T?> _showReelDialog<T>(
    WidgetBuilder builder, {
    bool Function(T? result)? keepPausedAfter,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    );
    _dialogRoute = route;
    _setPaused(_PauseCause.modal, true);
    T? result;
    try {
      return result = await navigator.push<T>(route);
    } finally {
      if (identical(_dialogRoute, route)) _dialogRoute = null;
      if (mounted) {
        final keepPaused =
            !_closeAfterDialog && (keepPausedAfter?.call(result) ?? false);
        if (!keepPaused) _setPaused(_PauseCause.modal, false);
        if (_closeAfterDialog) {
          _closeAfterDialog = false;
          _close();
        }
      }
    }
  }

  /// Shows the "this cannot be undone" confirmation the brief requires,
  /// then calls `delete_story_item`. Mirrors the house pattern already
  /// used for deleting a timeline moment
  /// (`moment_card.dart`'s `_showDeleteConfirmation` — same title/body
  /// copy shape) rather than inventing a new confirmation style.
  ///
  /// Deletion removes the item from BOTH surfaces at once (spec §3.1/
  /// §3.2: one row, one `deleted_at`). The server bumps
  /// `story_change_signals` on soft delete (spec §5.5) and every
  /// provider watching it refetches on its own, but a signal can be
  /// missed, so this screen also invalidates Home's ring summary itself
  /// (batch-4 review, Minor 4). It hides the item at once (by id,
  /// [_removedIds]), steps off it, and refreshes whichever pager backs it.
  Future<void> _confirmAndDelete(StoryItem item) async {
    if (_deleting) return;
    final confirmed = await _showReelDialog<bool>(
      keepPausedAfter: (ok) => ok == true,
      (dialogContext) => AlertDialog(
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

    // Still paused (modal) from the confirm: a delete slower than the
    // story's remaining time must not let the reel advance or close under
    // it, or a late failure goes untold (final review #2).
    final container = ProviderScope.containerOf(context);
    setState(() => _deleting = true);
    try {
      await ref.read(storyReadGatewayProvider).deleteItem(storyItemId: item.id);
    } catch (_) {
      if (mounted) {
        _releaseActionPause();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete this story.')),
        );
      }
      return;
    }
    // Batch-4 review, Minor 4: refresh Home's ring here too, before a
    // reconcile can close the reel. The signal can be missed, the same
    // reason [_maybeMarkViewed] invalidates it. Through the container, so
    // it runs even if the person closed the reel meanwhile.
    container.invalidate(storyRingSummaryProvider(widget.relationshipId));
    // Wave 4 (05 #6): the story's media leaves this phone's caches, and
    // the calendar month re-reads, as the ring does: the signal can be
    // missed.
    unawaited(
      container
          .read(storyMediaEvictorProvider)
          .evict([item.thumbnailKey, item.mediaKey]),
    );
    container.invalidate(
      storyDayCountsProvider(
        StoryDayRangeKey.month(
          relationshipId: widget.relationshipId,
          day: item.occurredOn,
        ),
      ),
    );
    if (!mounted) return;

    if (_placesMode) {
      container.invalidate(storyPlacesProvider);
      _stepOffPlaceItem(item.id);
      _releaseActionPause();
      return;
    }

    // Step off NOW, by id: hide it locally and reconcile, so the screen
    // never keeps showing a story that no longer exists (02 #1). The
    // refetch then confirms server truth.
    _removedIds.add(item.id);
    _onItemsChanged(_liveItems());
    _releaseActionPause();
    unawaited(_refreshPager());
  }

  /// Ends the pause a confirmed Delete or Remove-from-map held while its
  /// call was in flight. After any step-off, so the removed story never
  /// resumes for a frame.
  void _releaseActionPause() {
    setState(() => _deleting = false);
    _setPaused(_PauseCause.modal, false);
  }

  /// "Remove from map" (couple map, author only): the story stays, its
  /// place is removed for good.
  Future<void> _confirmAndRemovePlace(StoryItem item) async {
    if (_deleting) return;
    final confirmed = await _showReelDialog<bool>(
      keepPausedAfter: (ok) => ok == true,
      (dialogContext) => AlertDialog(
        title: const Text('Remove from our map?'),
        content: const Text('The story stays. Its place is removed for good.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Paused until the call returns, as Delete is (final review #2).
    final container = ProviderScope.containerOf(context);
    setState(() => _deleting = true);
    try {
      await container.read(storyPlacesRepositoryProvider).clear(item.id);
    } catch (_) {
      if (mounted) {
        _releaseActionPause();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't remove the place. Try again.")),
        );
      }
      return;
    }
    // The server's signal bump refreshes every map; this one updates now.
    container.invalidate(storyPlacesProvider);
    if (!mounted) return;
    _stepOffPlaceItem(item.id);
    _releaseActionPause();
  }

  /// Places mode: drop [id] from the fixed list and show what's left (the
  /// next item slides into the same index), or close when nothing is.
  void _stepOffPlaceItem(String id) {
    final at = _placeItems.indexWhere((i) => i.id == id);
    if (at == -1) return;
    setState(() => _placeItems.removeAt(at));
    if (_placeItems.isEmpty) {
      _close();
      return;
    }
    _startItem(_placeItems, at.clamp(0, _placeItems.length - 1));
  }

  @override
  void dispose() {
    _startSearchTimer?.cancel();
    _stopMedia();
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  /// Sends a chat message quoting the story the reply was started on
  /// ([_replyTarget], else [_current]) — Task 6, spec §5.4. Composes
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
  ///
  /// Idempotent across retries (02 #17): the same text to the same story
  /// reuses one client message id, so a retry after a lost answer is
  /// refused by the unique key (23505) and counted as sent, never posted
  /// twice. A send that has no answer in [kStoryReplySendTimeout] counts as
  /// failed and keeps the text for a retry.
  Future<void> _sendReply() async {
    final item = _replyTarget ?? _current;
    final text = _replyController.text.trim();
    if (item == null || text.isEmpty || _sendingReply) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // One client id per composed reply (02 #17): retrying the same text to
    // the same story reuses it, so messages' (sender, client_message_id)
    // unique key drops a duplicate whose first answer was lost.
    final draftKey = '${item.id}|$text';
    if (_replyDraftKey != draftKey) {
      _replyDraftKey = draftKey;
      _replyDraftId = const Uuid().v4();
    }
    final clientMessageId = _replyDraftId!;

    setState(() => _sendingReply = true);
    var sent = false;
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendTextMessage(
            relationshipId: widget.relationshipId,
            senderId: user.id,
            clientMessageId: clientMessageId,
            content: text,
            storyItemId: item.id,
          )
          .timeout(kStoryReplySendTimeout);
      sent = true;
    } on PostgrestException catch (e) {
      // 23505: an earlier attempt with this id already landed.
      sent = e.code == '23505';
    } catch (_) {
      sent = false;
    }
    // Tied to its story, not to the item on screen: no generation guard,
    // so the reel moving on never leaves Send disabled (batch-1 review,
    // Minor 4). Only a popped screen drops the result.
    if (!mounted) return;
    setState(() => _sendingReply = false);
    // Replace, don't queue: a retry's "Reply sent" must not wait behind the
    // earlier "Could not send" for its full display time.
    final messenger = ScaffoldMessenger.of(context)..removeCurrentSnackBar();
    if (sent) {
      _replyDraftKey = null;
      _replyDraftId = null;
      _replyController.clear();
      _replyFocusNode.unfocus();
      messenger.showSnackBar(const SnackBar(content: Text('Reply sent')));
    } else if (!_liveItems().any((i) => i.id == item.id)) {
      // Batch-5 review, Minor 2: its story went while the send was on its
      // way. Say so, as the deleted-while-typing path does; the text stays.
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'That story is no longer available. Your reply is still here.',
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
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
    // Day mode (spec §5.3) watches the day-scoped, expired-inclusive
    // provider; author mode watches the exact same
    // storyReelPagesProvider(key) Task 4 already wired — unchanged.
    // Places mode reads its own fixed list first, so author mode's provider
    // is never instantiated for it.
    final AsyncValue<List<StoryItem>> pagesAsync = _placesMode
        ? AsyncValue.data(_placeItems)
        : ref.watch(_itemsProvider());

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (pagesAsync.valueOrNull) {
        final List<StoryItem> raw => _buildLoaded(raw),
        null when pagesAsync.hasError => _ErrorState(
          onClose: _close,
          onRetry: () => unawaited(_refreshPager()),
        ),
        null => const _CenteredSpinner(),
      },
    );
  }

  /// The reel for a list that exists. A refresh keeps the previous list
  /// (R2), so this keeps rendering through it: no spinner, no lost
  /// keyboard.
  Widget _buildLoaded(List<StoryItem> raw) {
    // The deleted story is never drawn while the next one is found (M-1).
    if (_pagingPastDeleted) return const _CenteredSpinner();
    final occurredOn = widget.occurredOn;
    final items = _seekHold ?? _visible(raw);
    _shownItems = items;
    if (items.isEmpty) {
      // One author's ring: page forward once before saying there is
      // nothing; the spinner holds only while that single run pages.
      if (widget.dayAuthorId != null && !_authorFillDone) {
        if (!_pagerHasMore()) return _EmptyState(onClose: _close);
        _fillAuthorPage();
        return const _CenteredSpinner();
      }
      // A page that failed on the way is an error, not "nothing" (M-1).
      if (widget.dayAuthorId != null && _pagerHasError()) {
        return _ErrorState(onClose: _close, onRetry: _retryAuthorFill);
      }
      return _EmptyState(onClose: _close);
    }
    // Start once, where [_resolveStartIndex] says (owner ruling 3).
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_beginPlayback());
      });
    }
    final found = _currentIndexIn(items);
    final clampedIndex =
        found >= 0 ? found : _index.clamp(0, items.length - 1);
    // Owner ruling 2: the author can delete their own story wherever they
    // watch it: their reel, the calendar day, the map. delete_story_item
    // stays author-only server-side.
    final currentItem = _current ?? items[clampedIndex];
    // Until playback starts on the story [_resolveStartIndex] chose, the
    // fallback is items[0], a story the person may never see: no action
    // and no byline may act on or name it (final review #4).
    final started = _current != null;
    final myId = ref.read(currentUserProvider)?.id;
    final perItemAuthor = occurredOn != null || _placesMode;
    final isAuthor = myId != null && currentItem.authorId == myId;
    final canDeleteCurrent = isAuthor;
    // Replying is only offered on the PARTNER's item — replying to
    // your own story would quote yourself in your own chat, which
    // is not a sensible action and nothing in the spec asks for
    // it. Same per-item (not per-screen) derivation canDeleteCurrent
    // uses, since day mode can mix both partners' items.
    final isCurrentMine = perItemAuthor ? isAuthor : widget.isOwnReel;
    final partnerName = ref.watch(partnerNameProvider).valueOrNull;
    final authorLabel = isCurrentMine ? 'You' : (partnerName ?? 'Partner');
    final now = DateTime.now();
    final clockTime = occurredOn != null || _placesMode;
    // A map cluster mixes days, and a quoted story can be from any day:
    // those reels name the date too (final review #9).
    final withDate = _placesMode || widget.initialStoryItemId != null;
    final postedLabel = storyPostedLabel(
      currentItem.createdAt,
      now: now,
      clockTime: clockTime,
      withDate: withDate,
    );
    final postedSpokenLabel = storyPostedSpokenLabel(
      currentItem.createdAt,
      now: now,
      clockTime: clockTime,
      withDate: withDate,
    );
    // Spec §5.2: the poster sees Seen once the partner has watched. No
    // client privacy logic: the server masks has_been_viewed when seen
    // receipts are off. The map path has no server flag at all
    // (list_story_places returns no seen column; StoryPlace.fromRow sets
    // it true for the pins), so places mode shows no Seen and no faded
    // bars (final review #1).
    final seenBy =
        started &&
            !_placesMode &&
            isCurrentMine &&
            currentItem.hasBeenViewed
        ? (partnerName ?? 'Partner')
        : null;
    // Owner ruling 3: a partner's story I already watched shows faded in
    // the bars. A partner's view of MY story never fades it.
    final viewed = [
      for (final i in items)
        !_placesMode &&
            i.authorId != myId &&
            (i.hasBeenViewed || _markedItemIds.contains(i.id)),
    ];
    return _ReelBody(
      items: items,
      index: clampedIndex,
      current: currentItem,
      authorLabel: authorLabel,
      postedLabel: postedLabel,
      postedSpokenLabel: postedSpokenLabel,
      showByline: started,
      seenBy: seenBy,
      viewed: viewed,
      progress: _progressFraction,
      phase: _phase,
      pageLoading: _pageLoading,
      player: _player,
      image: _currentImage,
      onTapLeft: _onTapBack,
      onTapRight: _onTapNext,
      onRetry: () => _retryCurrent(manual: true),
      onNext: _onTapNext,
      onHoldStart: () => _setPaused(_PauseCause.hold, true),
      onHoldEnd: () => _setPaused(_PauseCause.hold, false),
      onTogglePause: _toggleAccessibilityPause,
      accessibilityPaused: _pauseCauses.contains(_PauseCause.accessibility),
      onDismiss: _close,
      onDelete: started && canDeleteCurrent
          ? () => unawaited(_confirmAndDelete(currentItem))
          : null,
      deleting: _deleting,
      onRemovePlace: started && _placesMode && isAuthor
          ? () => unawaited(_confirmAndRemovePlace(currentItem))
          : null,
      canReply: started && !isCurrentMine,
      replyController: _replyController,
      replyFocusNode: _replyFocusNode,
      sendingReply: _sendingReply,
      onSendReply: () => unawaited(_sendReply()),
    );
  }
}

class _ReelBody extends StatelessWidget {
  const _ReelBody({
    required this.items,
    required this.index,
    required this.current,
    required this.authorLabel,
    required this.postedLabel,
    required this.postedSpokenLabel,
    this.showByline = true,
    this.seenBy,
    required this.viewed,
    required this.progress,
    required this.phase,
    required this.player,
    required this.image,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onRetry,
    required this.onNext,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onTogglePause,
    required this.accessibilityPaused,
    required this.onDismiss,
    this.pageLoading = false,
    this.onDelete,
    this.deleting = false,
    this.onRemovePlace,
    this.canReply = false,
    this.replyController,
    this.replyFocusNode,
    this.sendingReply = false,
    this.onSendReply,
  });

  final List<StoryItem> items;
  final int index;

  /// The story on screen, by identity (R1) — never `items[index]`.
  final StoryItem current;

  /// The byline under the bars (R6): "You" or the partner's name, and
  /// when the story was posted ([storyPostedLabel]).
  final String authorLabel;
  final String postedLabel;
  final String postedSpokenLabel;

  /// False until the start story is chosen ([StoryReelHeader.showByline]).
  final bool showByline;

  /// The partner's name on my own story once they have seen it (spec
  /// §5.2); null hides the Seen chip.
  final String? seenBy;

  /// Per item, whether this viewer had already seen it
  /// ([StoryProgressBars.viewed]).
  final List<bool> viewed;
  final double progress;
  final _ItemPhase phase;

  /// True while the reel waits for the next page at the end of this one.
  final bool pageLoading;
  final StoryItemPlayer? player;

  /// The provider the screen already resolved for the CURRENT photo (fix
  /// round 1, F5) — passed straight to [_MediaView] rather than having it
  /// mint its own.
  final ImageProvider? image;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  /// The failure overlay's actions ([_ItemFailed]).
  final VoidCallback onRetry;
  final VoidCallback onNext;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  /// The screen-reader Pause/Play toggle, and whether it is paused now.
  final VoidCallback onTogglePause;
  final bool accessibilityPaused;
  final VoidCallback onDismiss;

  /// Non-null when the current story is the signed-in user's own (any
  /// mode; owner ruling 2).
  final VoidCallback? onDelete;

  /// True while a delete is in flight: the button stays visible but
  /// disabled, so a second tap cannot fire a second delete.
  final bool deleting;

  /// Couple map places mode, author only: removes the story's place.
  final VoidCallback? onRemovePlace;

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

  /// Below the safe area: the bars and header row (~64 dp) plus a fade.
  static const _kTopScrimHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final item = current;
    return _GestureLayer(
      holdThreshold: _holdThreshold,
      onHoldStart: onHoldStart,
      onHoldEnd: onHoldEnd,
      onTapLeft: onTapLeft,
      onTapRight: onTapRight,
      onTogglePause: onTogglePause,
      accessibilityPaused: accessibilityPaused,
      onDismiss: onDismiss,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: phase == _ItemPhase.failed
                ? _ItemFailed(onRetry: onRetry, onNext: onNext)
                : _MediaView(
                    item: item,
                    player: player,
                    image: image,
                    phase: phase,
                  ),
          ),
          if (phase == _ItemPhase.ready &&
              player is StoryItemPlayerStatus &&
              (player as StoryItemPlayerStatus).isBuffering)
            const Center(
              child: SizedBox(
                width: IconSizes.lg,
                height: IconSizes.lg,
                child: CircularProgressIndicator(
                  key: ValueKey('story-reel-buffering'),
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          // Batch-4 review, Minor 2: a scrim keeps the white bars, byline,
          // Seen and icons readable on a bright photo. Literal colours: the
          // reel is a fixed black surface in both themes. It never takes a
          // tap, so paging and the quick-exit band behave as before.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top + _kTopScrimHeight,
            child: const IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('story-reel-top-scrim'),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          // Fix round 1, F4: a Positioned pins the bars to the top edge
          // (a bare SafeArea stretched to full height and centred them).
          // R6: the byline and the reel's actions sit in a row under the
          // bars, so the buttons no longer cover them (02 #21).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.sm,
                  Spacing.sm,
                  Spacing.xs,
                  0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StoryProgressBars(
                      itemCount: items.length,
                      currentIndex: index,
                      currentProgress: progress,
                      viewed: viewed,
                    ),
                    const SizedBox(height: Spacing.xs),
                    StoryReelHeader(
                      authorLabel: authorLabel,
                      postedLabel: postedLabel,
                      postedSpokenLabel: postedSpokenLabel,
                      showByline: showByline,
                      seenBy: seenBy,
                      trailing: [
                        if (onRemovePlace != null)
                          IconButton(
                            key: const ValueKey('story-reel-remove-place'),
                            iconSize: IconSizes.md,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: const Icon(
                              Icons.wrong_location_outlined,
                              color: Colors.white,
                            ),
                            tooltip: 'Remove from map',
                            onPressed: deleting ? null : onRemovePlace,
                          ),
                        if (onDelete != null)
                          IconButton(
                            key: const ValueKey('story-reel-delete'),
                            iconSize: IconSizes.md,
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                            // Its own semantics node: the tooltip is its
                            // label.
                            tooltip: 'Delete this story',
                            onPressed: deleting ? null : onDelete,
                          ),
                        IconButton(
                          iconSize: IconSizes.md,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                          tooltip: 'Close story',
                          onPressed: onDismiss,
                        ),
                      ],
                    ),
                  ],
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
                // Opaque: a tap in the strip's padding never reaches the
                // navigation layer underneath (02 #27).
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: _ReplyComposer(
                    controller: replyController!,
                    focusNode: replyFocusNode!,
                    sending: sendingReply,
                    onSend: onSendReply!,
                  ),
                ),
              ),
            ),
          if (pageLoading)
            const Center(
              child: CircularProgressIndicator(
                key: ValueKey('story-reel-page-loading'),
                color: Colors.white,
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
    required this.onTogglePause,
    required this.accessibilityPaused,
    required this.onDismiss,
    required this.child,
  });

  final Duration holdThreshold;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  /// Screen-reader Pause/Play (02 #18): a persistent toggle, not a hold.
  final VoidCallback onTogglePause;
  final bool accessibilityPaused;
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
    // TripleTapDetector's quick-exit band sits above every route; taps
    // there must not also page the reel and mark stories seen on the way
    // out (05 #7).
    final quickExitBand = MediaQuery.paddingOf(context).top + kToolbarHeight;
    if (details.localPosition.dy < quickExitBand) return;
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
          // Batch-5 review, Nit 4: on iPhone, VoiceOver's double-tap and
          // hold is a real touch hold (pause only while held); the toggle
          // is the Actions rotor's "Pause story".
          hint: defaultTargetPlatform == TargetPlatform.iOS
              ? 'Swipe up or right for the next story, swipe down or left '
                    'for the previous one. To pause or play, use the Pause '
                    'story action.'
              : 'Swipe up or right for the next story, swipe down or left '
                    'for the previous one. Double-tap and hold to pause or '
                    'play.',
          onIncrease: widget.onTapRight,
          onDecrease: widget.onTapLeft,
          onLongPress: widget.onTogglePause,
          customSemanticsActions: {
            CustomSemanticsAction(
              label: widget.accessibilityPaused ? 'Play story' : 'Pause story',
            ): widget.onTogglePause,
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
    required this.image,
    required this.phase,
  });

  final StoryItem item;
  final StoryItemPlayer? player;

  /// The provider `_loadImage` resolved for THIS item (one mint per item,
  /// the same provider object that gated ready) — passed down rather than
  /// re-fetched here.
  ///
  /// Fix round 1, F5: this widget used to independently
  /// `ref.watch(storyMediaSignedUrlProvider(item.mediaKey))`, which
  /// minted a SECOND signed URL for every image item — one wasted
  /// `create_signed_url` round-trip per image, and worse, a second
  /// source of truth that could disagree with the first: the URL that
  /// gated `markViewed` was not necessarily the URL actually rendered
  /// here. This widget renders exactly what the screen resolved.
  final ImageProvider? image;
  final _ItemPhase phase;

  @override
  Widget build(BuildContext context) {
    if (item.mediaType == 'video') {
      // The real player owns its own texture/rendering when backed by a
      // VideoPlayerController; a fake test player has nothing visual to
      // present.
      final p = player;
      if (p is VideoControllerStoryItemPlayer) {
        final controller = p.controller;
        return AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 1
              : controller.value.aspectRatio,
          child: VideoPlayer(controller),
        );
      }
      return phase == _ItemPhase.loading
          ? const _ItemSpinner()
          : const ColoredBox(color: Colors.black);
    }
    final provider = image;
    if (provider == null) return const _ItemSpinner();
    return Stack(
      alignment: Alignment.center,
      children: [
        Image(
          key: const ValueKey('story-reel-image'),
          image: provider,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        if (phase == _ItemPhase.loading) const _ItemSpinner(),
      ],
    );
  }
}

class _ItemSpinner extends StatelessWidget {
  const _ItemSpinner();

  @override
  Widget build(BuildContext context) => const CircularProgressIndicator(
    key: ValueKey('story-reel-item-loading'),
    color: Colors.white,
  );
}

/// Shown in place of a story that could not load (02 #5): says so, and
/// offers Retry and Next, so the person is never stuck on a dead item.
class _ItemFailed extends StatelessWidget {
  const _ItemFailed({required this.onRetry, required this.onNext});

  final VoidCallback onRetry;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final buttonStyle = TextButton.styleFrom(foregroundColor: Colors.white);
    return Padding(
      padding: Spacing.horizontalLG,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: IconSizes.lg,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            "Couldn't load this story.",
            textAlign: TextAlign.center,
            style: textTheme.bodyLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: Spacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('story-reel-retry'),
                style: buttonStyle,
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
              const SizedBox(width: Spacing.sm),
              TextButton(
                key: const ValueKey('story-reel-next'),
                style: buttonStyle,
                onPressed: onNext,
                child: const Text('Next'),
              ),
            ],
          ),
        ],
      ),
    );
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
          top: Spacing.sm,
          right: Spacing.sm,
          child: SafeArea(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Close story',
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
  const _ErrorState({required this.onClose, required this.onRetry});

  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't load this story.",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: Spacing.md),
              TextButton(
                key: const ValueKey('story-reel-error-retry'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        Positioned(
          top: Spacing.sm,
          right: Spacing.sm,
          child: SafeArea(
            child: IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: 'Close story',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: onClose,
            ),
          ),
        ),
      ],
    );
  }
}
