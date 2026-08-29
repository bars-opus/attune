import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the capture preview', () {
    late String src;

    setUpAll(() {
      src = File(
        'lib/features/chat/presentation/screens/streak_camera_screen.dart',
      ).readAsStringSync();
    });

    test('plays the captured clip instead of the live camera', () {
      // Reviewing over a live viewfinder shows the user the room they are
      // standing in, not the thing they are deciding whether to send.
      expect(src, contains('VideoPlayerController.file'));

      // The player must actually be OPENED from the review flow. Checking
      // only that the class is referenced passes on a build that defines
      // the whole preview and never calls it.
      final opensBeforeSheet = RegExp(
        r'_startPreview_\(_segments\.first\.path\)[\s\S]{0,400}?showModalBottomSheet',
      ).hasMatch(src);
      expect(
        opensBeforeSheet,
        isTrue,
        reason: 'the preview must open before the review sheet, or the '
            'sheet sits over a live camera',
      );
    });

    test('the preview loops while the sheet is open', () {
      // A clip that plays once and freezes on a black last frame reads as
      // a crash mid-review.
      expect(src, contains('setLooping(true)'));
    });

    test('the preview is disposed on every exit path', () {
      // A leaked controller holds the decoder open, and a second
      // recording then competes with it for the hardware.
      //
      // Counts calls to the single teardown helper rather than raw
      // dispose() calls: disposal is centralised precisely so a new exit
      // path cannot forget half of it.
      expect(src, contains('Future<void> _disposePreview()'));

      final calls = RegExp(r'await _disposePreview\(\)')
          .allMatches(src)
          .length;
      expect(
        calls,
        greaterThanOrEqualTo(3),
        reason: 'reset, send and re-open must each tear the preview down',
      );

      // And the widget's own dispose, which cannot await.
      expect(src, contains('_previewController?.dispose()'));
    });

    test('cancel resets the camera rather than leaving the screen', () {
      // Cancel means "not that take" — it returns the user to a live
      // camera ready to record again, not out to the chat.
      expect(src, contains('_resetCapture'));
      // The old cancel path discarded and popped in one breath. Cancel
      // now resets; only the explicit close button leaves.
      final resetThenPop = src.contains(
        'await _resetCapture();\n      return;',
      );
      expect(
        resetThenPop,
        isTrue,
        reason: 'cancel must reset and stay, not pop the camera screen',
      );
    });

    test('a close button exits the camera entirely', () {
      // The only way out is now explicit, since cancel no longer leaves.
      expect(src, contains('Icons.close'));
    });

    test('the record button reappears while sending', () {
      // The ring is the only progress a streak upload shows. Hiding the
      // button whenever a preview exists hid it for the entire send.
      expect(
        src,
        contains('preview != null && !_isSending'),
        reason: 'review hides the button; sending must not',
      );
    });

    test('the lens can be flipped mid-recording', () {
      // setDescription routes to setDescriptionWhileRecording, which both
      // platform packages implement. Disposing the controller instead
      // would end the take.
      expect(src, contains('setDescription('));
      expect(
        src,
        isNot(contains('if (_isRecording || _cameras.length < 2) return;')),
        reason: 'flipping must not be blocked during a take',
      );
    });
  });
}
