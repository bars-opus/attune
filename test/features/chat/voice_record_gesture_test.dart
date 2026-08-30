import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// A recorder that never touches a microphone, and whose start() can be
/// made slow so the test can lift the finger mid-start — the case that
/// orphaned a live recording.
class _FakeRecorder extends VoiceRecorderService {
  _FakeRecorder({this.startDelay = Duration.zero});

  final Duration startDelay;

  bool started = false;
  bool stopped = false;
  bool cancelled = false;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> start() async {
    if (startDelay > Duration.zero) await Future<void>.delayed(startDelay);
    started = true;
  }

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
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Duration get elapsed => const Duration(seconds: 1);

  @override
  void dispose() {}
}

Widget _harness(_FakeRecorder recorder, {VoidCallback? onRecorded}) {
  return withScreenUtil(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: TextEditingController(),
          onSend: () {},
          showVoiceMessage: true,
          recorderFactory: () => recorder,
          onVoiceMessageRecorded: (_) => onRecorded?.call(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a brief press still records and sends, without a long hold', (
    tester,
  ) async {
    // The mic is a press-and-hold control. Binding start to onLongPressStart
    // means a ~500ms dead zone in which the user is holding, sees nothing,
    // and gets no recording at all if they release.
    final recorder = _FakeRecorder();
    var recorded = false;
    await tester.pumpWidget(
      _harness(recorder, onRecorded: () => recorded = true),
    );

    final mic = find.byIcon(Icons.mic_none_rounded);
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      recorder.started,
      isTrue,
      reason: 'recording must begin on press, not after a long-press delay',
    );

    await gesture.up();
    // Not pumpAndSettle: the recording UI animates continuously, so
    // settling never returns.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      recorder.stopped,
      isTrue,
      reason:
          'started=' +
          recorder.started.toString() +
          ' cancelled=' +
          recorder.cancelled.toString(),
    );
    expect(recorded, isTrue, reason: 'lifting the finger sends the recording');
  });

  testWidgets('releasing mid-start does not orphan a live recording', (
    tester,
  ) async {
    // start() is awaited before _isRecording flips true. If the finger
    // lifts inside that window the end handler returns early and nothing
    // ever stops the recorder — the mic stays live with no UI.
    final recorder = _FakeRecorder(
      startDelay: const Duration(milliseconds: 300),
    );
    await tester.pumpWidget(_harness(recorder));

    final mic = find.byIcon(Icons.mic_none_rounded);
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();

    // Let the slow start finish.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      recorder.stopped || recorder.cancelled,
      isTrue,
      reason:
          'a recording started after the finger lifted must be stopped, '
          'not left running with no way to reach it',
    );
  });

  testWidgets(
    'dragging up locks: the finger can lift and recording continues',
    (tester) async {
      final recorder = _FakeRecorder();
      var recorded = false;
      await tester.pumpWidget(
        _harness(recorder, onRecorded: () => recorded = true),
      );

      final mic = find.byIcon(Icons.mic_none_rounded);
      final gesture = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 60));

      // Past the 100px lock threshold.
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 60));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        recorder.stopped,
        isFalse,
        reason:
            'lifting after a lock must NOT end the recording — that is '
            'what locking is for',
      );
      expect(recorded, isFalse);
      expect(recorder.cancelled, isFalse);
    },
  );

  testWidgets('dragging left cancels, and nothing is sent', (tester) async {
    final recorder = _FakeRecorder();
    var recorded = false;
    await tester.pumpWidget(
      _harness(recorder, onRecorded: () => recorded = true),
    );

    final mic = find.byIcon(Icons.mic_none_rounded);
    final gesture = await tester.startGesture(tester.getCenter(mic));
    await tester.pump(const Duration(milliseconds: 60));

    // Past the 80px cancel threshold.
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 60));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(recorder.cancelled, isTrue, reason: 'a left drag discards it');
    expect(
      recorded,
      isFalse,
      reason: 'a cancelled recording must never reach the conversation',
    );
  });
}
