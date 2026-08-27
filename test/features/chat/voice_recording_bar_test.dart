import 'package:attune/features/chat/presentation/widgets/voice_recording_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  group('held stage', () {
    testWidgets('shows elapsed time formatted as mm:ss', (tester) async {
      await tester.pumpWidget(
        wrap(
          const VoiceRecordingBar(
            elapsed: Duration(minutes: 1, seconds: 23),
            amplitude: 0.5,
            isCancelling: false,
          ),
        ),
      );
      expect(find.text('01:23'), findsOneWidget);
      expect(find.text('slide to cancel'), findsOneWidget);
    });

    testWidgets('shows the cancel hint once isCancelling is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const VoiceRecordingBar(
            elapsed: Duration.zero,
            amplitude: 0.0,
            isCancelling: true,
          ),
        ),
      );
      expect(find.text('Release to cancel'), findsOneWidget);
      // The slide hint is replaced, not merely recolored — otherwise the
      // bar would show two contradictory instructions at once.
      expect(find.text('slide to cancel'), findsNothing);
    });

    testWidgets('does not offer locked-stage transport controls', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const VoiceRecordingBar(
            elapsed: Duration.zero,
            amplitude: 0.0,
            isCancelling: false,
          ),
        ),
      );
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
    });
  });

  group('locked stage', () {
    testWidgets('shows delete, pause and send instead of the slide hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          VoiceRecordingBar(
            elapsed: const Duration(seconds: 3),
            amplitude: 0.4,
            isCancelling: false,
            stage: VoiceRecordingStage.locked,
            onCancel: () {},
            onTogglePause: () {},
            onSend: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.text('slide to cancel'), findsNothing);
    });

    testWidgets('swaps pause for mic while paused', (tester) async {
      await tester.pumpWidget(
        wrap(
          VoiceRecordingBar(
            elapsed: const Duration(seconds: 3),
            amplitude: 0.0,
            isCancelling: false,
            stage: VoiceRecordingStage.locked,
            isPaused: true,
            onCancel: () {},
            onTogglePause: () {},
            onSend: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsNothing);
    });

    testWidgets('each transport control fires its callback', (tester) async {
      var cancelled = 0;
      var toggled = 0;
      var sent = 0;

      await tester.pumpWidget(
        wrap(
          VoiceRecordingBar(
            elapsed: const Duration(seconds: 3),
            amplitude: 0.4,
            isCancelling: false,
            stage: VoiceRecordingStage.locked,
            onCancel: () => cancelled++,
            onTogglePause: () => toggled++,
            onSend: () => sent++,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(cancelled, 1);
      expect(toggled, 1);
      expect(sent, 1);
    });
  });

  testWidgets('renders a long level history without overflowing', (
    tester,
  ) async {
    // The bar draws only the newest samples that fit; a history far longer
    // than the on-screen capacity must still lay out cleanly.
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 300,
          child: VoiceRecordingBar(
            elapsed: const Duration(seconds: 30),
            amplitude: 0.8,
            isCancelling: false,
            levels: List<double>.filled(500, 0.7),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
