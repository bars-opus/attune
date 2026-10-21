import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:clock/clock.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart'
    show kStoryImageHoldDuration;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';

/// How long one clip may take to become visible (signed, downloaded, first
/// frame on screen) before the viewer says it couldn't load it. Generous
/// for a slow mobile link. A timeout never spends a view.
const Duration kStreakClipLoadTimeout = Duration(seconds: 15);

/// How long leaving waits for this open's spend to answer before closing
/// anyway. The count only refreshes the bubble (realtime delivers it too);
/// a spend still unanswered settles in the background with the same open
/// id, so a dead link never holds the last frame on screen.
const Duration kStreakSpendCloseWait = Duration(seconds: 2);

/// How long a failed clip's message stays up before a multi-clip streak
/// moves on to the next clip.
const Duration kStreakClipFailureHold = Duration(seconds: 2);

/// Plays a streak's clips in order and spends one view the moment the
/// first clip is presented (first frame on screen). Backing out of a
/// still-loading viewer costs nothing.
///
/// The view is spent ONCE per viewing — never once per clip, or a
/// three-clip streak would burn a three-view budget in a single watch.
/// It is sent at presentation, not on exit: an app killed, a quick exit or
/// a PIN lock mid-watch tears the route down without an exit, and the view
/// used to go unspent (its replay window never started either). Each open
/// carries one open id, so the server charges it once however often the
/// spend is retried (mark_streak_viewed(p_message_id, p_open_id)).
///
/// Every clip is signed before the first one plays: the last view's spend
/// destroys the clips server-side while they are still playing, and the
/// storage policy then refuses to sign them.
class StreakViewerScreen extends ConsumerStatefulWidget {
  const StreakViewerScreen({
    super.key,
    required this.messageId,
    this.imageHoldDuration = kStoryImageHoldDuration,
    this.imageProviderBuilder,
    this.onDisposed,
  });

  final String messageId;

  /// Called when this viewer goes away by ANY path — a pop, or the route
  /// (or the whole tree) being torn down without one, where the push's
  /// future may never complete. The bubble uses it to release its
  /// one-viewer-per-row guard.
  final VoidCallback? onDisposed;

  /// Test seam, mirroring StoryReelScreen's own parameter of the same
  /// name: defaults to [kStoryImageHoldDuration] — the SAME constant the
  /// story reel uses, so a photo holds for the same 5 seconds whether it
  /// arrives as a story or a streak (spec §6.3 step 3's second decision).
  final Duration imageHoldDuration;

  /// Test seam: how a signed photo URL becomes an [ImageProvider].
  /// Production uses [NetworkImage]; tests hand in a decodable
  /// [MemoryImage] so the "first frame shown" signal can be exercised.
  final ImageProvider Function(String url)? imageProviderBuilder;

  @override
  ConsumerState<StreakViewerScreen> createState() => _StreakViewerScreenState();
}

class _StreakViewerScreenState extends ConsumerState<StreakViewerScreen>
    with WidgetsBindingObserver {
  List<StreakClip> _clips = const [];
  int _index = 0;
  VideoPlayerController? _controller;

  /// Drives a photo clip's hold (spec §6.3 step 3): a photo has no
  /// natural duration to advance on, so a plain Timer stands in for the
  /// video controller's own end-of-clip listener. It starts at the photo's
  /// first painted frame, never when its URL is signed: a slow download
  /// must not eat the hold. Also carries the short pause after a failed
  /// clip before moving on. Null otherwise. Held while the app is away.
  _HoldTimer? _imageHoldTimer;

  /// Fires [kStreakClipLoadTimeout] after a clip starts loading unless the
  /// clip has been presented by then. Held while the app is away: being
  /// in the background is not a failed load.
  _HoldTimer? _loadTimeoutTimer;

  /// The app is not visible (hidden or paused). Nothing plays and no hold
  /// runs until it is back (final review M-3): a clip sounding over the
  /// home screen, or a photo's hold running out behind the lock screen,
  /// is a view nobody is watching.
  bool _away = false;

  /// The generation whose photo hold has already been started, so the
  /// frameBuilder (called on every rebuild) starts it once per clip.
  int _holdStartedFor = -1;

  /// The signed URL for the current PHOTO clip. Separate from the video
  /// controller entirely — mutually exclusive by construction, since one
  /// clip is always exactly one media kind.
  String? _imageUrl;

  /// Bumped on every _playAt call so a late timer/listener callback from
  /// a clip the viewer has since left (advanced past, or this screen
  /// disposed) cannot mutate state that no longer belongs to it — this
  /// task's own "guard every post-await state write" requirement.
  int _generation = 0;

  /// True only when there is genuinely nothing to play — the clips are
  /// spent, expired, or the fetch failed. Deliberately NOT a "finished
  /// loading" flag: the previous version cleared one as soon as the clips
  /// arrived, before the controller existed, so the widget fell through
  /// to the unavailable branch and flashed an error before playing.
  bool _unavailable = false;

  /// True once a clip has actually been SHOWN: a video's first frame is on
  /// screen after playback started, or a photo's first frame decoded. Until
  /// then, leaving costs nothing — a tap or back gesture on the black
  /// loading screen used to spend the recipient's only view.
  bool _hasPresented = false;

  /// The server returned no clips: spent or expired. Spending is then a
  /// budget sync (the RPC answers 0) that flips both bubbles to Opened.
  bool _clipsGone = false;

  /// The current clip could not be shown: signing failed, the decoder
  /// refused it, or a photo's bytes never arrived. Shown in words, never
  /// spent on its own.
  bool _loadFailed = false;

  bool get _spendAllowed => _hasPresented || _clipsGone;

  @visibleForTesting
  bool get hasPresentedForTest => _hasPresented;

  /// One id per opening of this viewer: every spend attempt of this open,
  /// the first and any retry, carries it.
  final String _openId = const Uuid().v4();

  /// Read once up front so a spend owed at teardown can still be retried
  /// after this State is disposed (ref is unusable by then).
  late final StreakRepository _streaks;
  late final String _messageId;

  /// Signed URLs for every clip, in order (null = that clip failed to
  /// sign). Started as soon as the clips arrive; awaited before clip one.
  Future<List<String?>>? _signedUrls;

  @override
  void initState() {
    super.initState();
    _streaks = ref.read(streakRepositoryProvider);
    _messageId = widget.messageId;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  /// Away: pause the clip and hold the timers. Back: carry on where it
  /// stopped. Not a close — the view was spent at presentation, so closing
  /// would cost the recipient their (often only) view for a phone call;
  /// the app's PIN lock / quick exit, not this screen, decide whether the
  /// person who comes back may see it. Inactive alone (a pulled-down
  /// shade, an incoming-call banner) leaves it playing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_away) return;
        _away = true;
        _imageHoldTimer?.pause();
        _loadTimeoutTimer?.pause();
        final controller = _controller;
        if (controller != null && controller.value.isPlaying) {
          unawaited(controller.pause());
        }
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        _imageHoldTimer?.resume();
        _loadTimeoutTimer?.resume();
        _resumeClip();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Restarts the current video if it stopped short of its end (paused
  /// while away, or loaded while away and never started).
  void _resumeClip() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (!value.isInitialized || value.isPlaying) return;
    if (value.position >= value.duration) return;
    final generation = _generation;
    final index = _index;
    controller.play().catchError((Object error) {
      ChatLog.diagnostic('streak clip failed to resume', error);
      _clipFailed(index, generation);
    });
  }

  Future<void> _load() async {
    try {
      final clips = await _streaks.fetchClips(_messageId);
      if (!mounted) return;

      if (clips.isEmpty) {
        setState(() {
          _clipsGone = true;
          _unavailable = true;
        });
        return;
      }

      // No setState between the fetch and the first play: a frame drawn
      // in between is one the user sees as neither loading nor playing.
      _clips = clips;
      _signedUrls = _signAll(clips);
      await _playAt(0);
    } catch (error) {
      ChatLog.diagnostic('streak clips fetch failed', error);
      if (mounted) setState(() => _unavailable = true);
    }
  }

  /// Signs every clip at once. media_url is a STORAGE KEY, not a URL, and
  /// the bucket is private — handing the key straight to the player
  /// requests a path that does not exist. A clip that fails to sign reads
  /// null and is shown as failed when its turn comes.
  Future<List<String?>> _signAll(List<StreakClip> clips) {
    final chat = ref.read(chatRepositoryProvider);
    return Future.wait(
      clips.map((clip) async {
        try {
          return await chat.createSignedMediaUrl(clip.mediaUrl);
        } catch (error) {
          ChatLog.diagnostic('streak clip signing failed', error);
          return null;
        }
      }),
    );
  }

  Future<void> _playAt(int index) async {
    // Leave the outgoing clip BEFORE waiting on its release: its timers
    // are cancelled and the generation moves first, so a load timeout or
    // listener of the old clip cannot act during a slow dispose, and
    // nothing else can reach (and dispose again) a controller already on
    // its way out.
    _imageHoldTimer?.cancel();
    _imageHoldTimer = null;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    final generation = ++_generation;
    final outgoing = _controller;
    _controller = null;
    await outgoing?.dispose();
    if (!mounted || generation != _generation) return;
    if (index >= _clips.length) {
      await _finish();
      return;
    }
    _loadTimeoutTimer = _HoldTimer(kStreakClipLoadTimeout, () {
      ChatLog.diagnostic('streak clip load timed out', index);
      _clipFailed(index, generation);
    }, held: _away);

    // Signed up front (see _signAll); the first clip waits for all of them.
    final urls = _signedUrls;
    final signed = urls == null ? null : (await urls)[index];
    if (!mounted || generation != _generation) return;
    if (signed == null) {
      // Signing failed (transient, or the key is gone). Say so; nothing is
      // spent unless something was already shown.
      _clipFailed(index, generation);
      return;
    }

    // A photo has no natural duration to advance on (same reasoning as
    // the story reel's own image branch): hold it for imageHoldDuration,
    // then spend the view and close exactly as a finished video does
    // (spec §6.3 step 3's second decision). The hold starts from the
    // first painted frame — see _photoFramePainted.
    if (_clips[index].mediaKind == StreakClipKind.photo) {
      setState(() {
        _imageUrl = signed;
        _controller = null;
        _index = index;
        _loadFailed = false;
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(signed));
    try {
      await controller.initialize();
    } catch (error) {
      ChatLog.diagnostic('streak clip failed to open', error);
      _clipFailed(index, generation);
      // Not awaited: a controller whose platform player was never created
      // can wait on that creation forever inside dispose.
      unawaited(controller.dispose());
      return;
    }
    if (!mounted || generation != _generation) {
      await controller.dispose();
      return;
    }

    // Latched: the end-of-clip condition (position >= duration and not
    // playing) stays TRUE once reached, and the controller notifies on
    // every tick. Without this the advance fired repeatedly, each call
    // disposing the controller whose listener was still running — the
    // screen went black and never popped.
    var advanced = false;
    var presented = false;
    controller.addListener(() {
      if (advanced) return;
      if (!mounted || generation != _generation) return;
      final value = controller.value;
      // Presented = frames are actually moving: playing AND the position
      // has passed zero. An initialized-but-stalled stream (iOS buffering
      // on a bad link) sits on a black or frozen texture and is not a
      // view. video_player polls position about every 100 ms, so this
      // lags real presentation by at most that. Latched once.
      if (!presented && value.isPlaying && value.position > Duration.zero) {
        presented = true;
        _hasPresented = true;
        _loadTimeoutTimer?.cancel();
        _spendNow();
      }
      if (value.isInitialized &&
          value.position >= value.duration &&
          !value.isPlaying) {
        advanced = true;
        unawaited(_playAt(index + 1));
      }
    });

    setState(() {
      _controller = controller;
      _imageUrl = null;
      _index = index;
      _loadFailed = false;
    });
    // Loaded while the app was away: it starts when the app comes back
    // (_resumeClip), not over the home screen.
    if (_away) return;
    try {
      await controller.play();
    } catch (error) {
      // A frozen first frame must not pass for a playing clip: say so.
      // _clipFailed releases this controller (it is _controller by now).
      ChatLog.diagnostic('streak clip failed to play', error);
      _clipFailed(index, generation);
    }
  }

  /// The clip at [index] could not be shown (signing failed, the decoder
  /// or player refused it, its bytes never came, or it timed out). Never
  /// spends on its own. On the first clip the viewer stays on the message
  /// and leaving is free; on a later clip it shows the message briefly and
  /// moves on, so one bad segment does not end the streak. Past the last
  /// clip, _finish spends only if an earlier clip was presented.
  void _clipFailed(int index, int generation) {
    if (!mounted || generation != _generation) return;
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = null;
    // A new generation: a late initialize/decode for the failed clip is
    // discarded rather than replacing the message mid-hold.
    final failed = ++_generation;
    // Release the failed clip's player before dropping the reference. A
    // stalled stream that later recovers would otherwise play on — sound
    // over the chat after the viewer closed, with no view spent.
    final stale = _controller;
    if (stale != null) unawaited(stale.dispose());
    _showLoadFailed(index);
    if (index == 0) return;
    _imageHoldTimer = _HoldTimer(kStreakClipFailureHold, () {
      if (!mounted || failed != _generation) return;
      unawaited(_playAt(index + 1));
    }, held: _away);
  }

  /// Called from the photo's frameBuilder once a frame exists. Post-frame,
  /// so it runs after that frame is painted; once per clip.
  void _photoFramePainted() {
    final generation = _generation;
    if (_holdStartedFor == generation) return;
    _holdStartedFor = generation;
    final index = _index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      _hasPresented = true;
      _spendNow();
      _loadTimeoutTimer?.cancel();
      _loadTimeoutTimer = null;
      _imageHoldTimer?.cancel();
      _imageHoldTimer = _HoldTimer(widget.imageHoldDuration, () {
        if (!mounted || generation != _generation) return;
        unawaited(_playAt(index + 1));
      }, held: _away);
    });
  }

  /// The clip at [index] cannot be shown. Clears whatever was on screen
  /// (a previous clip must not linger as if it were this one) and says so.
  void _showLoadFailed(int index) {
    setState(() {
      _controller = null;
      _imageUrl = null;
      _index = index;
      _loadFailed = true;
    });
  }

  @visibleForTesting
  Future<void> playAtForTest(int index) => _playAt(index);

  /// The budget the server reported, once spent. Held so the close path
  /// can return it even when the spend already happened on an earlier
  /// call.
  int? _remaining;

  /// This open's first spend attempt, fired at presentation: true once the
  /// server answered. Never replaced, so the view is sent once per open.
  Future<bool>? _spend;

  /// The exit's settle (await the spend, retry once if it failed). Shared
  /// by every exit racing to it, and by teardown.
  Future<void>? _settled;

  /// Sends the spend for this open, once. Called the moment a clip is
  /// presented (and on exit for clips the server says are gone).
  void _spendNow() {
    _spend ??= _attemptSpend();
  }

  /// One spend attempt with this open's id. Never throws: a failure must
  /// not trap the viewer on the screen. Logged rather than swallowed: if
  /// the RPC is failing, the streak stays on "Play" across restarts
  /// because the SERVER never recorded the view, and a silent catch makes
  /// that indistinguishable from the UI simply not updating.
  Future<bool> _attemptSpend() async {
    try {
      _remaining = await _streaks.markViewed(_messageId, openId: _openId);
      return true;
    } catch (error) {
      ChatLog.diagnostic('mark streak viewed failed', error);
      return false;
    }
  }

  /// Waits briefly ([kStreakSpendCloseWait]) for the spend so the close
  /// can hand the bubble the count, retrying ONCE with the same open id if
  /// it failed — the server answers a repeat with the count it stored. A
  /// spend that has not answered by then is left to finish in the
  /// background, retried once there if it fails, exactly as teardown does.
  Future<void> _settleSpend() => _settled ??= () async {
    _spendNow();
    final spend = _spend!;
    final ok = await spend
        .then<bool?>((sent) => sent)
        .timeout(kStreakSpendCloseWait, onTimeout: () => null);
    if (ok == null) {
      unawaited(_retryIfFailed(spend));
    } else if (!ok) {
      await _attemptSpend().timeout(
        kStreakSpendCloseWait,
        onTimeout: () => false,
      );
    }
  }();

  /// Background settle for a spend nobody waits on any more: one retry,
  /// same open id, if it failed.
  Future<void> _retryIfFailed(Future<bool> spend) async {
    if (!await spend) await _attemptSpend();
  }

  /// Settles the view, then closes.
  ///
  /// Two steps rather than one, and the close is NOT inside the guard.
  /// _finish is re-entered by this screen's own PopScope when the pop it
  /// requests is intercepted; if closing lived in the memoised settle,
  /// that second call would never reach it and the route would never pop
  /// — a black, frozen screen.
  Future<void> _finish() async {
    // Nothing was shown (still loading, signing failed, bytes never came)
    // and the server has not said the clips are gone: leaving is free.
    if (!_spendAllowed) {
      _close();
      return;
    }
    await _settleSpend();
    _close();
  }

  /// Test seam for the completion path: playback running out calls
  /// _finish directly, with no gesture in flight, which is where the
  /// PopScope re-entrancy actually bites.
  @visibleForTesting
  Future<void> finishForTest() => _finish();

  /// Pops with whatever the server reported. Unguarded on purpose: this is
  /// the step that has to run on every exit, including the re-entrant one.
  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop(_remaining);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _imageHoldTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    _controller?.dispose();
    // Torn down after presentation without an exit (quick exit, PIN lock,
    // a parent popUntil): the spend was already sent. If it failed, retry
    // it once here with the same open id — the view WAS seen.
    final spend = _spend;
    if (spend != null && _settled == null) {
      _settled = _retryIfFailed(spend);
    }
    widget.onDisposed?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final imageUrl = _imageUrl;

    // canPop:false so the OS back gesture and the system back button route
    // through _finish rather than popping directly, which skipped the RPC
    // and left a watched streak uncharged.
    //
    // It does NOT block this screen's own Navigator.pop: a programmatic
    // pop reports didPop:true and closes regardless, which is why _close
    // works and why the didPop guard below is what prevents a double
    // spend rather than a deadlock.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_finish());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          // Opaque so the black letterbox around a clip, and the loading
          // screen itself, close on tap like the clip does.
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_finish()),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Three states while opening, matching the ephemeral video
              // viewer's original two plus the photo branch: a ready
              // video controller plays, a resolved photo URL renders as
              // an image, and anything else spins. The unavailable
              // message is reserved for the case where there is actually
              // nothing to play, so it can never appear mid-open.
              if (controller != null && controller.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                )
              else if (_loadFailed)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      "Couldn't load this streak. Try again in a moment.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                )
              else if (imageUrl != null)
                Center(
                  child: Image(
                    key: const ValueKey('streak-photo-view'),
                    image: (widget.imageProviderBuilder ?? _networkImage)(
                      imageUrl,
                    ),
                    fit: BoxFit.contain,
                    // Until a frame exists the photo is still downloading:
                    // show that it is loading. The first painted frame is
                    // when the person has SEEN it — the view becomes
                    // spendable and the hold starts.
                    frameBuilder: (context, child, frame, wasSyncLoaded) {
                      if (frame == null && !wasSyncLoaded) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [child, const _StreakLoadingIndicator()],
                        );
                      }
                      _photoFramePainted();
                      return child;
                    },
                    // Not an app-visible error banner, but not a silent
                    // black screen either: nothing is spent for this
                    // photo, and the person is told why.
                    errorBuilder: (_, __, ___) {
                      // Pinned to this clip: a late error from a photo
                      // already moved past must not flag the next one.
                      final generation = _generation;
                      final index = _index;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _clipFailed(index, generation);
                      });
                      return const SizedBox.shrink();
                    },
                  ),
                )
              else if (_unavailable)
                const Center(
                  child: Text(
                    'This streak is no longer available.',
                    style: TextStyle(color: Colors.white),
                  ),
                )
              else
                const Center(child: _StreakLoadingIndicator()),

              // Clip position, so a multi-clip streak does not feel like it
              // stalled between segments.
              if (_clips.length > 1)
                Positioned(
                  top: 56,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      '${_index + 1} / ${_clips.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),

              // An explicit way out while loading, so the black screen does
              // not invite a guess-tap. Same exit as everything else.
              Positioned(
                top: 8,
                left: 4,
                child: SafeArea(
                  child: IconButton(
                    // A small dark scrim so the X stays visible over a
                    // bright or white frame.
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.4),
                    ),
                    // A label rather than a tooltip: a tooltip is announced
                    // as well as the label, so "Close" would be read twice.
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      semanticLabel: 'Close',
                    ),
                    onPressed: () => unawaited(_finish()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ImageProvider _networkImage(String url) => NetworkImage(url);

/// A one-shot timer that can be held (the app went to the background) and
/// picked up again with the time it had left.
class _HoldTimer {
  _HoldTimer(this._left, this._onFire, {required bool held}) {
    if (!held) resume();
  }

  final VoidCallback _onFire;
  Duration _left;
  Timer? _timer;
  DateTime? _startedAt;
  bool _over = false;

  void pause() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    _left -= clock.now().difference(_startedAt!);
    if (_left.isNegative) _left = Duration.zero;
  }

  void resume() {
    if (_over || _timer != null) return;
    _startedAt = clock.now();
    _timer = Timer(_left, () {
      _over = true;
      _timer = null;
      _onFire();
    });
  }

  void cancel() {
    _over = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// Loading, as a spinner — or, under reduce motion, a still mark.
class _StreakLoadingIndicator extends StatelessWidget {
  const _StreakLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    if (reduceMotionOf(context)) {
      return const Icon(
        Icons.hourglass_top_rounded,
        key: ValueKey('streak-loading-static'),
        color: Colors.white70,
        size: 32,
        semanticLabel: 'Loading',
      );
    }
    return const CircularProgressIndicator();
  }
}
