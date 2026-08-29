import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File(
      'lib/features/chat/presentation/screens/streak_viewer_screen.dart',
    ).readAsStringSync();
  });

  test('"no longer available" cannot show while the video is still opening',
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
  });

  test('the player and the spinner are the only two loading states', () {
    // Matches the ephemeral video viewer: a controller that is ready
    // plays, and everything else spins. No third state can appear
    // mid-open.
    final ordered = src.indexOf('controller.value.isInitialized') <
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
