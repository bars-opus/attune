import 'package:attune/features/chat/presentation/screens/video_trim_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'confirm button is disabled when the source is shorter than the minimum duration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VideoTrimScreen(
            sourcePath: '/tmp/fake.mp4',
            sourceDuration: const Duration(
              milliseconds: 200,
            ), // under 500ms minimum
          ),
        ),
      );
      await tester.pump();

      final confirmButton = tester.widget<FilledButton>(
        find.byType(FilledButton),
      );
      expect(confirmButton.onPressed, isNull);
    },
  );

  testWidgets(
    'pre-positions the window to the full clip when source is already under the cap',
    (tester) async {
      const sourceDuration = Duration(seconds: 45); // under 3-minute cap
      await tester.pumpWidget(
        MaterialApp(
          home: VideoTrimScreen(
            sourcePath: '/tmp/fake.mp4',
            sourceDuration: sourceDuration,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('0:45'), findsWidgets);
    },
  );

  testWidgets(
    'pre-positions a maxDuration-wide window at the start when source exceeds the cap',
    (tester) async {
      const sourceDuration = Duration(minutes: 10); // over 3-minute cap
      await tester.pumpWidget(
        MaterialApp(
          home: VideoTrimScreen(
            sourcePath: '/tmp/fake.mp4',
            sourceDuration: sourceDuration,
          ),
        ),
      );
      await tester.pump();

      // The initially-selected window duration should be exactly the cap,
      // not the full 10-minute source.
      expect(find.textContaining('3:00'), findsWidgets);
    },
  );

  testWidgets('returns null when the user backs out without confirming', (
    tester,
  ) async {
    ({Duration start, Duration end})? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed: () async {
                  result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => const VideoTrimScreen(
                            sourcePath: '/tmp/fake.mp4',
                            sourceDuration: Duration(seconds: 30),
                          ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
