import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/voice_recording_scrim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Models a first-ever recording: the OS permission sheet sits up for a
/// second before the user taps Allow.
class _SlowPermissionRecorder extends _FakeRecorder {
  @override
  Future<bool> requestPermission() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    return true;
  }
}

class _DeniedRecorder extends _FakeRecorder {
  @override
  Future<bool> requestPermission() async => false;
}

class _FakeRecorder extends VoiceRecorderService {
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> start() async {}
  @override
  Future<VoiceRecording> stop() async => const VoiceRecording(
    localPath: '/tmp/f.m4a',
    durationMs: 1200,
    waveform: <int>[1],
  );
  @override
  Future<void> cancel() async {}
  @override
  Duration get elapsed => const Duration(seconds: 1);
  @override
  void dispose() {}
}

Widget _harnessWith(VoiceRecorderService Function() factory) => withScreenUtil(
  MaterialApp(
    home: Scaffold(
      body: ChatTextField(
        controller: TextEditingController(),
        onSend: () {},
        showVoiceMessage: true,
        recorderFactory: factory,
        onVoiceMessageRecorded: (_) {},
      ),
    ),
  ),
);

Widget _harness() => withScreenUtil(
  MaterialApp(
    home: Scaffold(
      body: ChatTextField(
        controller: TextEditingController(),
        onSend: () {},
        showVoiceMessage: true,
        recorderFactory: _FakeRecorder.new,
        onVoiceMessageRecorded: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('disposing mid-teardown leaves no overlay behind', (
    tester,
  ) async {
    // _hideScrim clears _scrimEntry BEFORE awaiting the fade, so a dispose
    // landing inside that await sees null and skips removal -- while the
    // resumed await touches a disposed controller. Navigating away during
    // the fade is the ordinary way to hit this.
    await tester.pumpWidget(_harness());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VoiceRecordingScrim), findsOneWidget);

    // Release: the fade starts (180ms reverse).
    await gesture.up();
    await tester.pump();
    // Tear the widget down mid-fade.
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(
      withScreenUtil(const MaterialApp(home: Scaffold(body: SizedBox()))),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.byType(VoiceRecordingScrim),
      findsNothing,
      reason: 'an overlay left up would cover the whole app',
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'the fade must not tick a disposed controller',
    );
  });

  testWidgets('the scrim appears within 200ms, before permission resolves', (
    tester,
  ) async {
    // Checklist 5.2: for operations bounded by an external dependency, the
    // first feedback must render within 200ms even if the full result
    // takes seconds. The OS permission sheet is exactly that case -- on a
    // first-ever recording the finger was held on the mic with nothing on
    // screen until the user tapped Allow.
    await tester.pumpWidget(_harnessWith(_SlowPermissionRecorder.new));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byType(VoiceRecordingScrim),
      findsOneWidget,
      reason: 'no feedback while the permission sheet is up',
    );

    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('a denied permission takes the scrim back down', (tester) async {
    // Raising the scrim early means every early-return path must also
    // lower it, or a refusal leaves the app under a black overlay.
    await tester.pumpWidget(_harnessWith(_DeniedRecorder.new));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(VoiceRecordingScrim), findsNothing);
  });
}
