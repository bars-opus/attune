import 'dart:async';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

final streakRepositoryProvider = Provider<StreakRepository>(
  (ref) => StreakRepository(),
);

/// Plays a streak's clips in order, then spends one view.
///
/// The view is spent ONCE per viewing, on completion or dismissal — never
/// once per clip, or a three-clip streak would burn a three-view budget
/// in a single watch.
class StreakViewerScreen extends ConsumerStatefulWidget {
  const StreakViewerScreen({
    super.key,
    required this.messageId,
    this.caption,
  });

  final String messageId;

  /// Rendered as an overlay while viewing, and nowhere else.
  final String? caption;

  @override
  ConsumerState<StreakViewerScreen> createState() => _StreakViewerScreenState();
}

class _StreakViewerScreenState extends ConsumerState<StreakViewerScreen> {
  List<StreakClip> _clips = const [];
  int _index = 0;
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _viewSpent = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final clips =
          await ref.read(streakRepositoryProvider).fetchClips(widget.messageId);
      if (!mounted) return;
      setState(() {
        _clips = clips;
        _loading = false;
      });
      if (clips.isNotEmpty) await _playAt(0);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAt(int index) async {
    await _controller?.dispose();
    if (index >= _clips.length) {
      await _finish();
      return;
    }

    final controller =
        VideoPlayerController.networkUrl(Uri.parse(_clips[index].mediaUrl));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    controller.addListener(() {
      final value = controller.value;
      if (value.isInitialized &&
          value.position >= value.duration &&
          !value.isPlaying) {
        unawaited(_playAt(index + 1));
      }
    });

    setState(() {
      _controller = controller;
      _index = index;
    });
    await controller.play();
  }

  /// Spends the view. Guarded so completion and an explicit dismissal
  /// cannot both charge it.
  Future<void> _finish() async {
    if (_viewSpent) return;
    _viewSpent = true;
    try {
      await ref.read(streakRepositoryProvider).markViewed(widget.messageId);
    } catch (_) {
      // A failed decrement must not trap the viewer on the screen; the
      // budget is server-owned and the next open re-reads it.
    }
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final caption = widget.caption;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => unawaited(_finish()),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(
                child: Text(
                  'This streak is no longer available.',
                  style: TextStyle(color: Colors.white),
                ),
              ),

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

            // The caption lives HERE and nowhere else: it is view-time
            // state, never part of the chat row or the conversations list.
            if (caption != null && caption.isNotEmpty)
              Positioned(
                left: 24,
                right: 24,
                bottom: 64,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
