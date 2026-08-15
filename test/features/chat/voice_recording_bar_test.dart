import 'package:attune/features/chat/presentation/widgets/voice_recording_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows elapsed time formatted as mm:ss', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecordingBar(
            elapsed: const Duration(minutes: 1, seconds: 23),
            amplitude: 0.5,
            isCancelling: false,
          ),
        ),
      ),
    );
    expect(find.text('01:23'), findsOneWidget);
    expect(find.text('Slide up to cancel'), findsOneWidget);
  });

  testWidgets('shows the cancel hint once isCancelling is true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceRecordingBar(
            elapsed: Duration.zero,
            amplitude: 0.0,
            isCancelling: true,
          ),
        ),
      ),
    );
    expect(find.text('Release to cancel'), findsOneWidget);
  });
}
