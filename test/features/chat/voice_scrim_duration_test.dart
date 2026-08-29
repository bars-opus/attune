import 'package:attune/features/chat/presentation/widgets/voice_recording_scrim.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Duration elapsed) => MaterialApp(
  home: Scaffold(
    body: VoiceRecordingScrim(
      animation: const AlwaysStoppedAnimation(1.0),
      data: ValueNotifier(VoiceScrimData(elapsed: elapsed)),
      micRect: const Rect.fromLTWH(300, 500, 40, 40),
    ),
  ),
);

/// AnimatedRollingCounter renders each digit as its own Text so it can roll
/// them independently, so the timer has to be read off the widget tree in
/// order rather than matched as one string.
String _readTimer(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(
      of: find.byType(Row).first,
      matching: find.byType(Text),
    ),
  );
  return texts.map((t) => t.data ?? '').join();
}

void main() {
  testWidgets('under a minute reads as plain seconds', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(seconds: 43)));
    expect(find.text(':'), findsNothing,
        reason: 'no minutes segment below 60s');
    expect(_readTimer(tester), '43');
  });

  testWidgets('past a minute reads as m:ss, not raw seconds',
      (tester) async {
    // The recorder runs to 5 minutes, so a plain seconds counter reached
    // "300" — which nobody reads as five minutes.
    await tester.pumpWidget(_wrap(const Duration(seconds: 700)));
    expect(_readTimer(tester), '11:40', reason: '700s is 11m 40s');
  });

  testWidgets('seconds are zero-padded against the colon', (tester) async {
    // "1:5" reads as one-and-a-half minutes to as many people as read it
    // as one minute five.
    await tester.pumpWidget(_wrap(const Duration(seconds: 65)));
    expect(_readTimer(tester), '1:05');
  });

  testWidgets('the recorder ceiling reads as a duration', (tester) async {
    await tester.pumpWidget(_wrap(const Duration(minutes: 5)));
    expect(_readTimer(tester), '5:00');
  });
}
