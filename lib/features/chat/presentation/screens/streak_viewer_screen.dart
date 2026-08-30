import 'dart:async';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';

/// Plays a streak's clips in order, then spends one view.
///
/// The view is spent ONCE per viewing, on completion or dismissal — never
/// once per clip, or a three-clip streak would burn a three-view budget
/// in a single watch.
class StreakViewerScreen extends ConsumerStatefulWidget {
  const StreakViewerScreen({super.key, required this.messageId});

  final String messageId;

  @override
  ConsumerState<StreakViewerScreen> createState() => _StreakViewerScreenState();
}

class _StreakViewerScreenState extends ConsumerState<StreakViewerScreen> {
  List<StreakClip> _clips = const [];
  int _index = 0;
  VideoPlayerController? _controller;

  /// True only when there is genuinely nothing to play — the clips are
  /// spent, expired, or the fetch failed. Deliberately NOT a "finished
  /// loading" flag: the previous version cleared one as soon as the clips
  /// arrived, before the controller existed, so the widget fell through
  /// to the unavailable branch and flashed an error before playing.
  bool _unavailable = false;
  bool _viewSpent = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final clips = await ref
          .read(streakRepositoryProvider)
          .fetchClips(widget.messageId);
      if (!mounted) return;

      if (clips.isEmpty) {
        setState(() => _unavailable = true);
        return;
      }

      // No setState between the fetch and the first play: a frame drawn
      // in between is one the user sees as neither loading nor playing.
      _clips = clips;
      await _playAt(0);
    } catch (error) {
      ChatLog.diagnostic('streak clips fetch failed', error);
      if (mounted) setState(() => _unavailable = true);
    }
  }

  Future<void> _playAt(int index) async {
    await _controller?.dispose();
    if (index >= _clips.length) {
      await _finish();
      return;
    }

    // media_url is a STORAGE KEY, not a URL, and the bucket is private —
    // handing the key straight to the player requests a path that does
    // not exist. Every other media path in chat signs first.
    final signed = await ref
        .read(chatRepositoryProvider)
        .createSignedMediaUrl(_clips[index].mediaUrl);
    if (!mounted) return;
    if (signed == null) {
      // The clips are gone (spent, or past the 30-minute window). Close
      // rather than sitting on a black screen.
      if (mounted) setState(() => _unavailable = true);
      await _finish();
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(signed));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    // Latched: the end-of-clip condition (position >= duration and not
    // playing) stays TRUE once reached, and the controller notifies on
    // every tick. Without this the advance fired repeatedly, each call
    // disposing the controller whose listener was still running — the
    // screen went black and never popped.
    var advanced = false;
    controller.addListener(() {
      if (advanced) return;
      final value = controller.value;
      if (value.isInitialized &&
          value.position >= value.duration &&
          !value.isPlaying) {
        advanced = true;
        unawaited(_playAt(index + 1));
      }
    });

    setState(() {
      _controller = controller;
      _index = index;
    });
    await controller.play();
  }

  /// The budget the server reported, once spent. Held so the close path
  /// can return it even when the spend already happened on an earlier
  /// call.
  int? _remaining;

  /// Spends the view, then closes.
  ///
  /// Two steps rather than one, and the close is NOT inside the guard.
  /// _finish is re-entered by this screen's own PopScope when the pop it
  /// requests is intercepted; if closing lived in the guarded body, that
  /// second call would return early at _viewSpent and the route would
  /// never pop — a black, frozen screen.
  Future<void> _finish() async {
    await _spendView();
    _close();
  }

  /// Test seam for the completion path: playback running out calls
  /// _finish directly, with no gesture in flight, which is where the
  /// PopScope re-entrancy actually bites.
  @visibleForTesting
  Future<void> finishForTest() => _finish();

  /// Charges the view exactly once, however many exits race to it.
  Future<void> _spendView() async {
    if (_viewSpent) return;
    _viewSpent = true;
    try {
      _remaining = await ref
          .read(streakRepositoryProvider)
          .markViewed(widget.messageId);
    } catch (error) {
      // A failed decrement must not trap the viewer on the screen; the
      // budget is server-owned and the next open re-reads it.
      //
      // Logged rather than swallowed: if the RPC is failing, the streak
      // stays on "Play" across restarts because the SERVER never recorded
      // the view — and a silent catch makes that indistinguishable from
      // the UI simply not updating.
      ChatLog.diagnostic('mark streak viewed failed', error);
    }
  }

  /// Pops with whatever the server reported. Unguarded on purpose: this is
  /// the step that has to run on every exit, including the re-entrant one.
  void _close() {
    if (!mounted) return;
    Navigator.of(context).pop(_remaining);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

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
          onTap: () => unawaited(_finish()),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Two states while opening, matching the ephemeral video
              // viewer: a ready controller plays, anything else spins. The
              // unavailable message is reserved for the case where there is
              // actually nothing to play, so it can never appear mid-open.
              if (controller != null && controller.value.isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
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
                const Center(child: CircularProgressIndicator()),

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
            ],
          ),
        ),
      ),
    );
  }
}
