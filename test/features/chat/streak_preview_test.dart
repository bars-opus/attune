import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Plan B, Task 2 extracted capture (permissions, camera switching, segment
// recording, the lens flip, close/flip visibility during review) out of
// StreakCameraScreen into CaptureCameraScreen, a destination-neutral
// module — streak_camera_contract_test.dart pins the streak BEHAVIOUR
// these tests assert on unchanged. What stayed on StreakCameraScreen (the
// adapter) is the review preview player and the review-cancel/send flow
// built on top of it; what moved to CaptureCameraScreen is the lens flip
// and the close/flip/record-button visibility gating during that review.
// This file follows those same moves so it keeps asserting the same
// guarantees against where they now live, under their new names
// (`_startPreview` not `_startPreview_`, `reset()` not `_resetCapture()`,
// the `reviewing` flag CaptureCameraScreen is handed instead of its own
// `preview != null` check).
void main() {
  group('the capture preview', () {
    late String adapterSrc;
    late String captureSrc;

    setUpAll(() {
      adapterSrc =
          File(
            'lib/features/chat/presentation/screens/streak_camera_screen.dart',
          ).readAsStringSync();
      captureSrc =
          File(
            'lib/features/chat/presentation/screens/capture_camera_screen.dart',
          ).readAsStringSync();
    });

    test('plays the captured clip instead of the live camera', () {
      // Reviewing over a live viewfinder shows the user the room they are
      // standing in, not the thing they are deciding whether to send.
      expect(adapterSrc, contains('VideoPlayerController.file'));

      // The player must actually be OPENED from the review flow. Checking
      // only that the class is referenced passes on a build that defines
      // the whole preview and never calls it.
      //
      // _startPreview now takes the whole CapturedMedia (`_startPreview(media)`),
      // not just its path (`_startPreview(media.path)`) — spec §6.3 step 3
      // widened it to also branch on media.type for a photo take, which a
      // photo-only build needs to know without a second parameter.
      final opensBeforeSheet = RegExp(
        r'_startPreview\(media\)[\s\S]{0,400}?showModalBottomSheet',
      ).hasMatch(adapterSrc);
      expect(
        opensBeforeSheet,
        isTrue,
        reason:
            'the preview must open before the review sheet, or the '
            'sheet sits over a live camera',
      );
    });

    test('the preview loops while the sheet is open', () {
      // A clip that plays once and freezes on a black last frame reads as
      // a crash mid-review.
      expect(adapterSrc, contains('setLooping(true)'));
    });

    test('the preview is disposed on every exit path', () {
      // A leaked controller holds the decoder open, and a second
      // recording then competes with it for the hardware.
      //
      // Counts calls to the single teardown helper rather than raw
      // dispose() calls: disposal is centralised precisely so a new exit
      // path cannot forget half of it.
      expect(adapterSrc, contains('Future<void> _disposePreview()'));

      final calls =
          RegExp(r'await _disposePreview\(\)').allMatches(adapterSrc).length;
      expect(
        calls,
        greaterThanOrEqualTo(3),
        reason: 'reset, send and re-open must each tear the preview down',
      );

      // And the widget's own dispose, which cannot await.
      expect(adapterSrc, contains('_previewController?.dispose()'));
    });

    test('cancel resets the camera rather than leaving the screen', () {
      // Cancel means "not that take" — it returns the user to a live
      // camera ready to record again, not out to the chat. The extracted
      // CaptureCameraScreen owns that reset now (renamed `reset()`,
      // `_resetCapture()` before Task 2, and made public so an embedding
      // adapter can call it); the adapter's job is to call it rather than
      // pop.
      expect(captureSrc, contains('Future<void> reset() async {'));
      final resetThenReturn = adapterSrc.contains(
        'await _captureKey.currentState?.reset();\n      return;',
      );
      expect(
        resetThenReturn,
        isTrue,
        reason: 'cancel must reset and stay, not pop the camera screen',
      );
    });

    test('a close button exits the camera entirely', () {
      // The only way out is now explicit, since cancel no longer leaves.
      // Close (and the rest of the live-viewfinder chrome) is owned by
      // the extracted CaptureCameraScreen.
      expect(captureSrc, contains('Icons.close'));
    });

    test('the record button reappears while sending', () {
      // The ring is the only progress a streak upload shows. Hiding the
      // button whenever a review is under way must not also hide it
      // during the send itself. `reviewing` is CaptureCameraScreen's own
      // mirror of the pre-extraction `preview != null` check, driven by
      // the embedding adapter.
      expect(
        captureSrc,
        contains('reviewing && !_isSending'),
        reason: 'review hides the button; sending must not',
      );
    });

    test('the lens can be flipped mid-recording', () {
      // setDescription routes to setDescriptionWhileRecording, which both
      // platform packages implement. Disposing the controller instead
      // would end the take. Camera switching is owned by the extracted
      // CaptureCameraScreen.
      expect(captureSrc, contains('setDescription('));
      expect(
        captureSrc,
        isNot(contains('if (_isRecording || _cameras.length < 2) return;')),
        reason: 'flipping must not be blocked during a take',
      );
    });

    test('the close and flip controls hide during review', () {
      // The send sheet owns that moment: closing would discard the take
      // silently, and flipping would spin up a camera nobody is looking
      // at behind the preview. CaptureCameraScreen gates its own controls
      // on the `reviewing` flag the embedding adapter hands it, in place
      // of the pre-extraction `preview == null` check on its own state.
      expect(
        captureSrc,
        contains('if (!reviewing && !_isSending) ...['),
        reason:
            'both top controls must be gated on there being no take '
            'under review, and none during the send',
      );
    });
  });
}
