// lib/core/services/media/visible_only_playback.dart
import 'dart:async';

import 'package:video_player/video_player.dart';

/// Plays a video only while Attune's content is on screen
/// (appContentVisibleProvider; stories Wave 3). [start] plays now when
/// visible, or on the next return. Leaving pauses it, and coming back plays
/// it again, but only what this paused or was asked to start: a pause the
/// person chose stays theirs.
///
/// Pausing at the first `inactive` also stops video_player's own
/// lifecycle observer from resuming it on `resumed` (it resumes only what
/// was playing at `paused`), which would otherwise play behind the Safety
/// lock check.
class VisibleOnlyPlayback {
  VisibleOnlyPlayback({required bool Function() isVisible})
    : _isVisible = isVisible;

  final bool Function() _isVisible;
  VideoPlayerController? _controller;
  bool _owed = false;

  void start(VideoPlayerController controller) {
    _controller = controller;
    _owed = true;
    if (_isVisible()) _playOwed();
  }

  void onVisibility(bool visible) {
    final controller = _controller;
    if (controller == null) return;
    if (!visible) {
      if (controller.value.isPlaying) {
        _owed = true;
        unawaited(controller.pause().catchError((Object _) {}));
      }
      return;
    }
    if (_owed) _playOwed();
  }

  /// The controller is going away (disposed or replaced): forget it.
  void clear() {
    _controller = null;
    _owed = false;
  }

  void _playOwed() {
    _owed = false;
    unawaited(_controller!.play().catchError((Object _) {}));
  }
}
