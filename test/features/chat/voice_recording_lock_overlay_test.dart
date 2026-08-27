import 'package:attune/features/chat/presentation/widgets/voice_recording_lock_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('renders the padlock and the upward chevron at rest', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 0)));
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);
  });

  testWidgets('chevron fades out as the finger approaches the lock', (
    tester,
  ) async {
    Opacity chevronOpacity() => tester.widget<Opacity>(
      find.ancestor(
        of: find.byIcon(Icons.keyboard_arrow_up_rounded),
        matching: find.byType(Opacity),
      ),
    );

    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 0)));
    expect(chevronOpacity().opacity, 1.0);

    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 1)));
    expect(chevronOpacity().opacity, 0.0);
  });

  testWidgets('the pill rises as progress increases', (tester) async {
    Offset iconTop() =>
        tester.getTopLeft(find.byIcon(Icons.lock_outline_rounded));

    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 0)));
    final atRest = iconTop().dy;

    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 1)));
    // Transform.translate moves it upward, so y decreases.
    expect(iconTop().dy, lessThan(atRest));
  });

  testWidgets('out-of-range progress is clamped rather than throwing', (
    tester,
  ) async {
    // The caller derives progress from a raw drag distance; a value outside
    // 0..1 must not produce an invalid Opacity or a lerp assertion.
    for (final p in <double>[-5, 1.8]) {
      await tester.pumpWidget(wrap(VoiceRecordingLockOverlay(progress: p)));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('does not intercept pointer events', (tester) async {
    // The overlay floats above the composer during a live press-and-hold;
    // absorbing pointers would break the very gesture that shows it.
    await tester.pumpWidget(wrap(const VoiceRecordingLockOverlay(progress: 0.5)));
    // Scoped to this widget's own subtree — Material's internals contribute
    // their own IgnorePointers, so a bare byType finder would match those.
    expect(
      find.descendant(
        of: find.byType(VoiceRecordingLockOverlay),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
  });
}
