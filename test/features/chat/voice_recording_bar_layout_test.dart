import 'package:attune/core/widgets/animated_rolling_counter.dart';
import 'package:attune/features/chat/presentation/widgets/voice_recording_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(primary: Color(0xFF2E7D5B)),
      ),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('a locked bar keeps exactly one way to send and one to discard',
      (tester) async {
    // An earlier pass put a stop icon here wired to onSend, which left
    // the locked bar with two send controls and no way to throw a take
    // away.
    await tester.pumpWidget(_wrap(const VoiceRecordingBar(
      elapsed: Duration(seconds: 10),
      amplitude: 0.4,
      isCancelling: false,
      stage: VoiceRecordingStage.locked,
    )));

    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
  });

  testWidgets('the duration rolls rather than jumping', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceRecordingBar(
      elapsed: Duration(seconds: 10),
      amplitude: 0.4,
      isCancelling: false,
    )));

    expect(find.byType(AnimatedRollingCounter), findsOneWidget);
  });

  testWidgets('a recording dot marks the live state', (tester) async {
    await tester.pumpWidget(_wrap(const VoiceRecordingBar(
      elapsed: Duration(seconds: 3),
      amplitude: 0.2,
      isCancelling: false,
    )));

    expect(find.byKey(const ValueKey('voice-recording-dot')), findsOneWidget);
  });

  testWidgets('slide-to-cancel is offered while held, not once locked',
      (tester) async {
    await tester.pumpWidget(_wrap(const VoiceRecordingBar(
      elapsed: Duration(seconds: 3),
      amplitude: 0.2,
      isCancelling: false,
    )));
    expect(find.textContaining('slide to cancel'), findsOneWidget);

    await tester.pumpWidget(_wrap(const VoiceRecordingBar(
      elapsed: Duration(seconds: 3),
      amplitude: 0.2,
      isCancelling: false,
      stage: VoiceRecordingStage.locked,
    )));
    await tester.pump(const Duration(milliseconds: 300));

    // Nothing is holding a locked take, so the hint must not still read
    // as though a finger were down.
    expect(find.textContaining('slide to cancel'), findsNothing);
  });
}
