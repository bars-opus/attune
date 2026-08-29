import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
import 'package:attune/features/chat/presentation/widgets/voice_recording_bar.dart';
import 'package:attune/features/chat/presentation/widgets/voice_recording_scrim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _FakeRecorder extends VoiceRecorderService {
  bool started = false;
  bool stopped = false;
  bool cancelled = false;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async => started = true;

  @override
  Future<VoiceRecording> stop() async {
    stopped = true;
    return const VoiceRecording(
      localPath: '/tmp/fake.m4a',
      durationMs: 1200,
      waveform: <int>[1, 2, 3],
    );
  }

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Duration get elapsed => const Duration(seconds: 1);

  @override
  void dispose() {}
}

Widget _harness(_FakeRecorder recorder, Haptics haptics) {
  return withScreenUtil(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: TextEditingController(),
          onSend: () {},
          showVoiceMessage: true,
          showGames: true,
          recorderFactory: () => recorder,
          haptics: haptics,
          onVoiceMessageRecorded: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('haptics', () {
    testWidgets('fire on press-to-record, on lock, and on cancel', (
      tester,
    ) async {
      // Counted rather than asserted on the source: a source check cannot
      // tell "fires once, on the right transition" from "fires on every
      // pointer move", and the second is what a naive placement produces.
      final haptics = FakeHaptics();
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, haptics));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));

      expect(haptics.lightCount, 1, reason: 'press-to-record');

      // Up past the lock threshold.
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      expect(haptics.mediumCount, 1, reason: 'swipe-to-lock');

      // Further drag inside the locked stage must not re-fire.
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(haptics.mediumCount, 1, reason: 'lock fires once, not per move');

      await gesture.up();
      await tester.pump();
    });

    testWidgets('a cancel drag fires exactly one haptic', (tester) async {
      final haptics = FakeHaptics();
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, haptics));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      final before = haptics.mediumCount;

      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(-70, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(haptics.mediumCount, before + 1, reason: 'crossing into cancel');

      // Dragging further while already cancelling must not re-fire.
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(haptics.mediumCount, before + 1);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(recorder.cancelled, isTrue);
    });
  });

  group('the recording composer', () {
    testWidgets('keeps the mic exactly where it was before the press', (
      tester,
    ) async {
      // The button must not jump when recording starts: the finger is
      // already on it, and a shifted target makes the lock and cancel
      // drags read from the wrong origin.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final idle = tester.getCenter(find.byIcon(Icons.mic_none_rounded));

      final gesture = await tester.startGesture(idle);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 300));

      final recording = tester.getCenter(find.byIcon(Icons.mic_rounded));
      expect(
        (recording.dx - idle.dx).abs(),
        lessThan(1.0),
        reason: 'mic moved horizontally from $idle to $recording',
      );

      await gesture.up();
      await tester.pump();
    });

    testWidgets('the held stage shows no composer bar or send control', (
      tester,
    ) async {
      // The scrim carries the counter, waveform and hint, so a bar down
      // here would be a second panel competing with it. Send happens by
      // releasing the hold; a tappable send would be a second way to do
      // what lifting the finger already does.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('voice-held-send')), findsNothing);
      expect(find.byType(VoiceRecordingBar), findsNothing);

      // Releasing still sends.
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(recorder.stopped, isTrue);
    });
  });

  group('the recording scrim', () {
    testWidgets('dims the screen and centres the counter and waveform', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      expect(
        find.byType(VoiceRecordingScrim),
        findsNothing,
        reason: 'no scrim before recording',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(VoiceRecordingScrim), findsOneWidget);

      // The counter belongs on the scrim, vertically centred — not in a
      // bar down at the composer.
      final counter = find.byKey(const ValueKey('voice-scrim-counter'));
      expect(counter, findsOneWidget);
      final screen = tester.getSize(find.byType(MaterialApp)).height;
      expect(
        tester.getCenter(counter).dy,
        lessThan(screen * 0.75),
        reason: 'counter sits at screen centre, not at the composer',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the white recording bar is gone', (tester) async {
      // The scrim is already dark, so the bar's surface-coloured container
      // would be a second, competing panel.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(VoiceRecordingBar), findsNothing);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('comes down when the recording ends', (tester) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(VoiceRecordingScrim), findsOneWidget);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byType(VoiceRecordingScrim),
        findsNothing,
        reason: 'an overlay left up would block the whole app',
      );
    });

    testWidgets('the lock pill sits directly above the mic', (tester) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final mic = tester.getCenter(find.byIcon(Icons.mic_rounded));
      final pill = tester.getCenter(find.byType(VoiceLockPill));

      expect(
        (pill.dx - mic.dx).abs(),
        lessThan(2.0),
        reason: 'pill at $pill is not above the mic at $mic',
      );
      expect(pill.dy, lessThan(mic.dy), reason: 'pill sits above');

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });
  });
}
