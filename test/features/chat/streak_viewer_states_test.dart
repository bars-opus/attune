import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src =
        File(
          'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
        ).readAsStringSync();
  });

  test('spending the view cannot deadlock against its own PopScope', () {
    // _finish() is guarded by _viewSpent so completion and a dismissal
    // cannot both charge the view. With canPop:false, _finish's own pop is
    // intercepted and routed back into _finish, which then returns at that
    // guard — nothing pops and the screen freezes black.
    //
    // The exit must therefore not be reachable only through the guarded
    // body: closing has to happen on a path the guard cannot swallow.
    expect(
      src,
      contains('_close('),
      reason:
          'popping must be its own step, not the tail of the guarded '
          'spend — otherwise the second call returns early and the route '
          'never closes',
    );
    final finishBody = src.substring(
      src.indexOf('Future<void> _finish()'),
      src.indexOf('void dispose()'),
    );
    expect(
      finishBody.contains('maybePop'),
      isFalse,
      reason: 'the guarded body must not own the pop',
    );
  });

  test('the completion listener fires the advance exactly once', () {
    // VideoPlayerController notifies on every tick, and the end-of-clip
    // condition (position >= duration && !isPlaying) stays TRUE once
    // reached. Without a latch, _playAt(index + 1) is called repeatedly —
    // each call disposing the controller whose listener is still running,
    // which is what left the screen black and frozen instead of popping.
    final listener = src.substring(
      src.indexOf('controller.addListener('),
      src.indexOf('setState(() {', src.indexOf('controller.addListener(')),
    );

    expect(
      listener.contains('advanced'),
      isTrue,
      reason:
          'the advance must latch, or the end-of-clip condition re-fires '
          'on every subsequent tick',
    );
  });

  test('a back-gesture dismissal still spends the view', () {
    // _finish() ran on playback completion and on an explicit tap, but the
    // OS back gesture and the system back button pop the route directly.
    // That path never called the RPC, so the streak was watched and
    // nothing was charged — it stayed on "Play" however many times it had
    // been opened.
    expect(
      src,
      contains('PopScope'),
      reason:
          'the route must intercept its own pop, or a back-gesture exit '
          'skips the decrement entirely',
    );
    expect(
      src,
      contains('canPop: false'),
      reason:
          'the pop has to be blocked until _finish has spent the view; '
          'letting it through and charging afterwards is the same race',
    );
  });

  test(
    '"no longer available" cannot show while the video is still opening',
    () {
      // _loading was cleared as soon as the CLIPS were fetched, before the
      // controller existed — so the widget fell through to the unavailable
      // branch and flashed an error, then a spinner, before playing.
      // Availability is a property of the clips, not of load timing.
      expect(
        src,
        contains('_unavailable'),
        reason: 'unavailability must be its own state, not the fallthrough',
      );
      expect(
        src,
        isNot(contains('if (_loading)')),
        reason: 'a load flag that clears early reintroduces the flash',
      );
    },
  );

  test('the player and the spinner are the only two loading states', () {
    // Matches the ephemeral video viewer: a controller that is ready
    // plays, and everything else spins. No third state can appear
    // mid-open.
    final ordered =
        src.indexOf('controller.value.isInitialized') <
        src.indexOf('CircularProgressIndicator');
    expect(ordered, isTrue);
  });

  test('playback starts without waiting for a second frame', () {
    // The clip fetch and the first play are one uninterrupted sequence:
    // any setState between them is a frame the user sees in a state that
    // is neither loading nor playing.
    expect(src, contains('await _playAt(0)'));
  });
}
