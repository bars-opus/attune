// Stories Wave 3: the chat stays mounted behind the privacy cover, so a
// recording in progress is no longer disposed when Attune leaves the
// screen. It is locked and paused, kept for the person to resume, send or
// delete, and the microphone stops.
import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _PausableRecorder extends VoiceRecorderService {
  _PausableRecorder({this.startDelay = Duration.zero});

  final Duration startDelay;
  bool started = false, stopped = false, cancelled = false, paused = false;
  int resumes = 0;

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
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
    resumes++;
  }

  @override
  bool get isPaused => paused;

  @override
  Duration get elapsed => const Duration(seconds: 1);

  @override
  void dispose() {}
}

Widget _harness(
  _PausableRecorder recorder, {
  VoidCallback? onRecorded,
  Haptics? haptics,
}) {
  return withScreenUtil(
    MaterialApp(
      home: Scaffold(
        body: ChatTextField(
          controller: TextEditingController(),
          onSend: () {},
          showVoiceMessage: true,
          recorderFactory: () => recorder,
          onVoiceMessageRecorded: (_) => onRecorded?.call(),
          haptics: haptics ?? const SystemHaptics(),
        ),
      ),
    ),
  );
}

void main() {
  final mic = find.byIcon(Icons.mic_none_rounded);
  void life(WidgetTester t, AppLifecycleState s) =>
      t.binding.handleAppLifecycleStateChanged(s);

  testWidgets('a locked recording is paused and kept when Attune leaves the '
      'screen, and does not listen again on its own', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 60));
    await g.moveBy(const Offset(0, -120)); // past the lock threshold
    await t.pump(const Duration(milliseconds: 60));
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isFalse);

    life(t, AppLifecycleState.inactive);
    await t.pump();
    expect(r.paused, isTrue, reason: 'the microphone stops behind the cover');
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isTrue);
    expect(r.resumes, 0);
    expect(r.stopped || r.cancelled || recorded, isFalse, reason: 'kept');
  });

  testWidgets('a held recording interrupted by a call is locked and paused: '
      'never sent and never lost', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 120));
    expect(r.started, isTrue);

    life(t, AppLifecycleState.inactive);
    await t.pump();
    await g.cancel(); // the system takes the touch
    await t.pump(const Duration(milliseconds: 100));
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 100));
    expect(r.paused, isTrue);
    expect(r.stopped, isFalse);
    expect(r.cancelled, isFalse);
    expect(recorded, isFalse);
  });

  testWidgets('regression guard: the first-use microphone alert (an inactive '
      'while starting) leaves the recording alone (Review Focus 2)', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder(startDelay: const Duration(milliseconds: 300));
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 50));
    life(t, AppLifecycleState.inactive);
    await t.pump();
    life(t, AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 400));
    expect(r.started, isTrue);
    expect(r.paused, isFalse);
    await g.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(r.stopped, isTrue);
    expect(recorded, isTrue);
  });

  // Fix round 1 (batch 3 review #2): the system can cancel the touch
  // BEFORE the inactive arrives (a Control Centre pull, an Android swipe
  // home). A cancel is not a release: the take is locked and kept.
  testWidgets('a held recording whose touch the system cancels before '
      'Attune leaves is locked and paused: never sent', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 120));
    expect(r.started, isTrue);

    await g.cancel();
    await t.pump();
    life(t, AppLifecycleState.inactive);
    await t.pump();
    expect(recorded, isFalse);
    expect(r.stopped, isFalse);
    expect(r.cancelled, isFalse);
    expect(r.paused, isTrue);
  });

  // Fix round 1 (review #3): a real leave (hidden) while start() is still
  // running pauses the recording as soon as it has started.
  testWidgets('a recording that finishes starting after Attune has left '
      'is paused at once: no microphone while hidden', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder(startDelay: const Duration(milliseconds: 300));
    var recorded = false;
    await t.pumpWidget(_harness(r, onRecorded: () => recorded = true));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 50));
    life(t, AppLifecycleState.inactive);
    life(t, AppLifecycleState.hidden);
    await t.pump(const Duration(milliseconds: 400));
    expect(r.started, isTrue);
    expect(r.paused, isTrue, reason: 'paused while still hidden');
    await g.cancel();
    await t.pump(const Duration(milliseconds: 100));
    expect(r.stopped || r.cancelled || recorded, isFalse, reason: 'kept');
  });

  // Fix round 1 (review #4): leaving buzzes at most once, even on a
  // synthesized inactive -> hidden -> paused burst.
  testWidgets('leaving mid-recording buzzes at most once', (t) async {
    addTearDown(() => life(t, AppLifecycleState.resumed));
    final r = _PausableRecorder();
    final haptics = FakeHaptics();
    await t.pumpWidget(_harness(r, haptics: haptics));
    final g = await t.startGesture(t.getCenter(mic));
    await t.pump(const Duration(milliseconds: 120));
    expect(r.started, isTrue);
    final before = haptics.mediumCount + haptics.lightCount;

    life(t, AppLifecycleState.inactive);
    life(t, AppLifecycleState.hidden);
    life(t, AppLifecycleState.paused);
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(r.paused, isTrue);
    expect(
      haptics.mediumCount + haptics.lightCount - before,
      lessThanOrEqualTo(1),
    );
    life(t, AppLifecycleState.hidden);
    life(t, AppLifecycleState.inactive);
    life(t, AppLifecycleState.resumed);
    await g.cancel();
    await t.pump(const Duration(milliseconds: 100));
  });
}
