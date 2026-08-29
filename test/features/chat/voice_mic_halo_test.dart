import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
import 'package:attune/features/chat/presentation/widgets/voice_mic_halo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _primary = Color(0xFF2E7D5B);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(primary: _primary),
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('the mic halo', () {
    testWidgets('is a filled primary disc while recording', (tester) async {
      await tester.pumpWidget(_wrap(const VoiceMicHalo(
        amplitude: 0.4,
        isRecording: true,
        child: Icon(Icons.mic_rounded),
      )));

      final disc = tester.widget<Container>(
        find.byKey(const ValueKey('voice-mic-disc')),
      );
      expect((disc.decoration! as BoxDecoration).color, _primary);
    });

    testWidgets('renders no disc or halo when idle', (tester) async {
      await tester.pumpWidget(_wrap(const VoiceMicHalo(
        amplitude: 0,
        isRecording: false,
        child: Icon(Icons.mic_none_rounded),
      )));

      expect(find.byKey(const ValueKey('voice-mic-disc')), findsNothing);
      expect(find.byKey(const ValueKey('voice-mic-halo')), findsNothing);
    });

    testWidgets('the halo grows with the voice', (tester) async {
      await tester.pumpWidget(_wrap(const VoiceMicHalo(
        amplitude: 0.1,
        isRecording: true,
        child: Icon(Icons.mic_rounded),
      )));
      await tester.pump(const Duration(milliseconds: 200));
      final quiet =
          tester.getSize(find.byKey(const ValueKey('voice-mic-halo')));

      await tester.pumpWidget(_wrap(const VoiceMicHalo(
        amplitude: 0.9,
        isRecording: true,
        child: Icon(Icons.mic_rounded),
      )));
      await tester.pump(const Duration(milliseconds: 200));
      final loud =
          tester.getSize(find.byKey(const ValueKey('voice-mic-halo')));

      expect(
        loud.width,
        greaterThan(quiet.width),
        reason: 'the halo is the voice made visible; a fixed ring says '
            'nothing the disc does not',
      );
    });
  });

  group('the lock pill', () {
    testWidgets('shows a padlock above a chevron', (tester) async {
      await tester.pumpWidget(_wrap(const VoiceLockPill(dragProgress: 0)));

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('the chevron fades as the lock is approached',
        (tester) async {
      await tester.pumpWidget(_wrap(const VoiceLockPill(dragProgress: 0)));
      await tester.pump();
      final far = tester.widget<Opacity>(
        find.byKey(const ValueKey('voice-lock-chevron')),
      );

      await tester.pumpWidget(_wrap(const VoiceLockPill(dragProgress: 0.95)));
      await tester.pump(const Duration(milliseconds: 200));
      final near = tester.widget<Opacity>(
        find.byKey(const ValueKey('voice-lock-chevron')),
      );

      // The arrow says "keep going"; at the threshold it has nothing left
      // to say and the padlock speaks for itself.
      expect(near.opacity, lessThan(far.opacity));
    });
  });
}
