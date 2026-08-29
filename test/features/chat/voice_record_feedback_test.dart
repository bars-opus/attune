import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
import 'package:attune/features/chat/presentation/widgets/voice_mic_halo.dart';
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

      // Scoped to the scrim: the composer keeps an invisible copy of the
      // mic to hold the gesture and the slot, so a bare byIcon finder
      // matches two widgets.
      final recording = tester.getCenter(
        find.descendant(
          of: find.byType(VoiceRecordingScrim),
          matching: find.byType(VoiceMicHalo),
        ),
      );
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

    testWidgets('the mic and lock pill are drawn ABOVE the black backdrop', (
      tester,
    ) async {
      // The scrim covers the whole screen, so anything left in the
      // composer is behind the black -- dimmed, and reading as disabled
      // while it is the very control the finger is holding.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final scrim = find.byType(VoiceRecordingScrim);
      expect(
        find.descendant(of: scrim, matching: find.byType(VoiceMicHalo)),
        findsOneWidget,
        reason: 'the mic and its ring belong on the scrim',
      );
      expect(
        find.descendant(of: scrim, matching: find.byType(VoiceLockPill)),
        findsOneWidget,
        reason: 'the lock pill belongs on the scrim',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the mic on the scrim keeps its composer position', (
      tester,
    ) async {
      // The finger is already on that button: drawing it anywhere else
      // would leave the gesture reading from one place and the visible
      // control sitting in another.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final idle = tester.getCenter(find.byIcon(Icons.mic_none_rounded));
      final gesture = await tester.startGesture(idle);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final onScrim = tester.getCenter(
        find.descendant(
          of: find.byType(VoiceRecordingScrim),
          matching: find.byType(VoiceMicHalo),
        ),
      );
      expect(
        (onScrim.dx - idle.dx).abs(),
        lessThan(1.0),
        reason: 'mic drawn at $onScrim, pressed at $idle',
      );
      expect((onScrim.dy - idle.dy).abs(), lessThan(1.0));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the scrim draws the mic at its full size, unclipped', (
      tester,
    ) async {
      // The composer's slot is a 40px icon box. Positioning the halo into
      // that rect directly would clip the 84px disc and its ring down to
      // icon size.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(VoiceRecordingScrim),
                matching: find.byKey(const ValueKey('voice-mic-disc')),
              ),
            )
            .width,
        VoiceMicHalo.disc,
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the cancel hint sits inline with the ring', (tester) async {
      // Vertically aligned with the mic, not stacked under the waveform:
      // the hint describes a drag that starts at the ring, so it should
      // read along the path the finger takes.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final ring = tester.getCenter(
        find.descendant(
          of: find.byType(VoiceRecordingScrim),
          matching: find.byKey(const ValueKey('voice-mic-disc')),
        ),
      );
      final hint = tester.getCenter(
        find.byKey(const ValueKey('voice-scrim-cancel-hint')),
      );

      expect(
        (hint.dy - ring.dy).abs(),
        lessThan(4.0),
        reason: 'hint at $hint is not inline with the ring at $ring',
      );
      expect(hint.dx, lessThan(ring.dx), reason: 'hint sits left of the ring');

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('a red delete button sits at the left end of that row', (
      tester,
    ) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final delete = find.byKey(const ValueKey('voice-scrim-delete'));
      expect(delete, findsOneWidget);

      final hint = tester.getCenter(
        find.byKey(const ValueKey('voice-scrim-cancel-hint')),
      );
      final deleteCentre = tester.getCenter(delete);
      expect(
        deleteCentre.dx,
        lessThan(hint.dx),
        reason: 'delete sits at the far left, before the hint',
      );
      expect(
        (deleteCentre.dy - hint.dy).abs(),
        lessThan(4.0),
        reason: 'delete is on the same row as the hint',
      );

      // Red, so its meaning is legible before the label is read. A bare
      // isNotNull check passes for white, which is the whole point of the
      // colour.
      final icon = tester.widget<Icon>(
        find.descendant(of: delete, matching: find.byType(Icon)),
      );
      final colour = icon.color!;
      expect(colour.r, greaterThan(0.7), reason: 'dominant red channel');
      expect(colour.g, lessThan(0.6), reason: 'not white or grey');
      expect(colour.b, lessThan(0.6));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('tapping delete actually discards the take', (tester) async {
      // The scrim sits under an IgnorePointer so it never steals the drag
      // that lock and cancel read from. A tap target added inside that
      // subtree is decorative unless it is deliberately excluded.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      // Finger up first: the delete button is for a hold that has already
      // been locked or released, not a competitor to the live gesture.
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey('voice-scrim-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        recorder.cancelled,
        isTrue,
        reason: 'the delete button must discard, not merely render',
      );
      expect(recorder.stopped, isFalse, reason: 'discard is not a send');
    });

    testWidgets('the cancel row slides in from the ring, the pill from below', (
      tester,
    ) async {
      // Both use the app's existing ShakeTransition: horizontal for the
      // cancel row (positive offset = starts right, travels left toward
      // the hint's resting place) and vertical for the pill (positive =
      // starts low, rises). Asserted by position mid-flight rather than by
      // widget type, so a ShakeTransition wired with the wrong axis or a
      // zero offset still fails.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      // One frame in: the entrance has begun but is nowhere near settled.
      await tester.pump(const Duration(milliseconds: 16));

      final earlyDelete = tester.getCenter(
        find.byKey(const ValueKey('voice-scrim-delete')),
      );
      final earlyPill = tester.getCenter(find.byType(VoiceLockPill));

      // Let both entrances finish.
      await tester.pump(const Duration(milliseconds: 1200));

      final restDelete = tester.getCenter(
        find.byKey(const ValueKey('voice-scrim-delete')),
      );
      final restPill = tester.getCenter(find.byType(VoiceLockPill));

      expect(
        earlyDelete.dx,
        greaterThan(restDelete.dx + 20),
        reason: 'delete must travel leftward: $earlyDelete -> $restDelete',
      );
      expect(
        earlyPill.dy,
        greaterThan(restPill.dy + 20),
        reason: 'pill must rise: $earlyPill -> $restPill',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the entrances replay on a SECOND recording', (tester) async {
      // ShakeTransition is a TweenAnimationBuilder, which animates from
      // its begin value only on first build. If the overlay's element is
      // reused across recordings the second take shows no motion at all --
      // the exact failure the streak uptick had.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      Future<Offset> recordAndSampleDelete() async {
        final g = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
        );
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 16));
        final early = tester.getCenter(
          find.byKey(const ValueKey('voice-scrim-delete')),
        );
        await tester.pump(const Duration(milliseconds: 1200));
        final rest = tester.getCenter(
          find.byKey(const ValueKey('voice-scrim-delete')),
        );
        await g.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        return Offset(early.dx - rest.dx, 0);
      }

      final firstTravel = await recordAndSampleDelete();
      final secondTravel = await recordAndSampleDelete();

      expect(firstTravel.dx, greaterThan(20));
      expect(
        secondTravel.dx,
        greaterThan(20),
        reason: 'second recording did not animate: $secondTravel',
      );
    });

    testWidgets('the delete icon sits on a plain white disc', (tester) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final box = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('voice-scrim-delete')),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      // Opaque white, not a translucent red wash: the red belongs to the
      // glyph, which needs a solid ground to read against the scrim.
      expect(decoration.color, Colors.white);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the cancel hint sits beside the delete button', (
      tester,
    ) async {
      // Centred in the leftover space, the text drifted far from the
      // button it labels. It reads as that button's caption only when it
      // is adjacent to it.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final deleteRight =
          tester
              .getRect(find.byKey(const ValueKey('voice-scrim-delete')))
              .right;
      final hintLeft =
          tester
              .getRect(find.byKey(const ValueKey('voice-scrim-cancel-hint')))
              .left;

      expect(
        hintLeft - deleteRight,
        lessThan(48.0),
        reason: 'hint starts at $hintLeft, button ends at $deleteRight',
      );
      expect(
        hintLeft,
        greaterThan(deleteRight),
        reason: 'hint sits to the right of the button, not over it',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the composer stops hit-testing under the scrim', (
      tester,
    ) async {
      // The scrim's delete button overlaps the composer's leading icon.
      // Both hit-test unless the covered composer opts out, and whichever
      // wins the arena decides what a tap does -- which silently made an
      // earlier version of the delete test pass through the wrong widget.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      // Anchored on the games icon, which the harness renders to the
      // right of the mic and which the scrim covers.
      final composerIgnores = find.ancestor(
        of: find.byIcon(Icons.sports_esports_outlined),
        matching: find.byType(IgnorePointer),
      );
      expect(
        tester
            .widgetList<IgnorePointer>(composerIgnores)
            .any((w) => w.ignoring),
        isTrue,
        reason: 'composer icons must not hit-test beneath the scrim',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the lock pill clears the ring by a margin', (tester) async {
      // A pill resting on the ring's edge reads as part of it. The gap has
      // to survive the ring growing, which is what pulled it down before.
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final pillBottom = tester.getRect(find.byType(VoiceLockPill)).bottom;
      final ringTop =
          tester
              .getRect(
                find.descendant(
                  of: find.byType(VoiceRecordingScrim),
                  matching: find.byType(CircularProgressIndicator),
                ),
              )
              .top;

      expect(
        ringTop - pillBottom,
        greaterThanOrEqualTo(8.0),
        reason:
            'pill bottom $pillBottom sits too close to ring top '
            '$ringTop',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('the lock pill sits directly above the mic', (tester) async {
      final recorder = _FakeRecorder();
      await tester.pumpWidget(_harness(recorder, FakeHaptics()));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.mic_none_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));

      final mic = tester.getCenter(
        find.descendant(
          of: find.byType(VoiceRecordingScrim),
          matching: find.byType(VoiceMicHalo),
        ),
      );
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
