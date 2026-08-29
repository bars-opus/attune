import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
import 'package:attune/features/chat/presentation/widgets/voice_mic_halo.dart';
import 'package:flutter/material.dart';
import 'package:attune/features/chat/presentation/widgets/streak_record_button.dart';
import 'package:flutter_test/flutter_test.dart';

const _primary = Color(0xFF2E7D5B);

Widget _wrap(Widget child) => MaterialApp(
  theme: ThemeData(colorScheme: const ColorScheme.light(primary: _primary)),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('the mic halo', () {
    testWidgets('is a filled primary disc while recording', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.4,
            isRecording: true,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );

      final disc = tester.widget<Container>(
        find.byKey(const ValueKey('voice-mic-disc')),
      );
      expect((disc.decoration! as BoxDecoration).color, _primary);
    });

    testWidgets('renders no disc or halo when idle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0,
            isRecording: false,
            child: Icon(Icons.mic_none_rounded),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('voice-mic-disc')), findsNothing);
      expect(find.byKey(const ValueKey('voice-mic-halo')), findsNothing);
    });

    testWidgets('the halo grows with the voice', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.1,
            isRecording: true,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final quiet = tester.getSize(
        find.byKey(const ValueKey('voice-mic-halo')),
      );

      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.9,
            isRecording: true,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final loud = tester.getSize(find.byKey(const ValueKey('voice-mic-halo')));

      expect(
        loud.width,
        greaterThan(quiet.width),
        reason:
            'the halo is the voice made visible; a fixed ring says '
            'nothing the disc does not',
      );
    });

    testWidgets('a progress ring shows how much of the cap is used', (
      tester,
    ) async {
      // Voice notes cap at five minutes. Without a ring the user has no
      // idea how close they are until the recorder cuts them off.
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.3,
            isRecording: true,
            progress: 0.5,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );

      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, 0.5);
    });

    testWidgets('no ring when idle', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0,
            isRecording: false,
            child: Icon(Icons.mic_none_rounded),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the mic glyph follows onPrimary, not a hardcoded white', (
      tester,
    ) async {
      // Asserted in a scheme whose onPrimary is BLACK: with a light
      // primary disc, a hardcoded white glyph vanishes into it. A
      // light-mode assertion cannot catch this, since onPrimary is white
      // there and both implementations agree.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFB8E6C8),
              onPrimary: Color(0xFF11221A),
            ),
          ),
          home: const Scaffold(
            body: Center(
              child: VoiceMicHalo(
                amplitude: 0.3,
                isRecording: true,
                child: Icon(Icons.mic_rounded),
              ),
            ),
          ),
        ),
      );

      final theme = tester.widget<IconTheme>(
        find.descendant(
          of: find.byKey(const ValueKey('voice-mic-disc')),
          matching: find.byType(IconTheme),
        ),
      );
      expect(theme.data.color, const Color(0xFF11221A));
    });

    testWidgets('the ring and halo disappear once locked', (tester) async {
      // Nothing is holding a locked take, so a progress ring around a
      // button the finger has left is noise — the bar owns that state.
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.3,
            isRecording: true,
            isLocked: true,
            progress: 0.4,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('voice-mic-halo')), findsNothing);
    });

    testWidgets('the disc and ring match the streak record button', (
      tester,
    ) async {
      // Both are the same control -- press and hold to capture -- so a
      // voice mic noticeably smaller than the streak button reads as a
      // different, lesser affordance.
      await tester.pumpWidget(
        _wrap(
          const VoiceMicHalo(
            amplitude: 0.0,
            isRecording: true,
            progress: 0.5,
            child: Icon(Icons.mic_rounded),
          ),
        ),
      );

      expect(
        tester.getSize(find.byKey(const ValueKey('voice-mic-disc'))).width,
        VoiceMicHalo.disc,
      );
      // Asserted against the streak button's own constants, so the two
      // cannot drift apart silently.
      expect(VoiceMicHalo.disc, StreakRecordButton.discDiameter);
      expect(VoiceMicHalo.arcStroke, StreakRecordButton.arcStroke);
      expect(
        VoiceMicHalo.arcDiameter,
        StreakRecordButton.discDiameter + StreakRecordButton.gap * 2,
      );

      final arc = tester.getSize(find.byType(CircularProgressIndicator));
      expect(arc.width, VoiceMicHalo.arcDiameter);
    });
  });

  group('the lock pill', () {
    testWidgets('shows a padlock above a chevron', (tester) async {
      await tester.pumpWidget(_wrap(const VoiceLockPill(dragProgress: 0)));

      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
    });

    testWidgets('the chevron fades as the lock is approached', (tester) async {
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
