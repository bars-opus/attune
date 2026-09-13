import 'package:attune/features/chat/presentation/widgets/reply_composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness({required Widget child, bool reduceMotion = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    );
  }

  testWidgets('opens from the composer edge before settling at full height', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        child: ReplyComposerPreview(
          quotedText: 'A message worth answering',
          onClose: () {},
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 90));
    final midHeight = tester.getSize(find.byType(ReplyComposerPreview)).height;
    final midRail = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('reply-preview-accent-rail')),
    );
    final midContent = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('reply-preview-content-opacity')),
    );
    expect(midHeight, greaterThan(0));
    expect(midRail.heightFactor, inExclusiveRange(0, 1));
    expect(midContent.opacity.value, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    final settledHeight =
        tester.getSize(find.byType(ReplyComposerPreview)).height;
    expect(settledHeight, greaterThan(midHeight));
    expect(
      find.textContaining('Replying to', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('A message worth answering', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('honors reduce motion with an immediate settled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        reduceMotion: true,
        child: ReplyComposerPreview(
          quotedText: 'Still understandable without motion',
          onClose: () {},
        ),
      ),
    );

    final rail = tester.widget<FractionallySizedBox>(
      find.byKey(const ValueKey('reply-preview-accent-rail')),
    );
    final content = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('reply-preview-content-opacity')),
    );
    final surface = tester.widget<ScaleTransition>(
      find.byKey(const ValueKey('reply-preview-surface-motion')),
    );
    expect(rail.heightFactor, 1);
    expect(content.opacity.value, 1);
    expect(surface.scale.value, 1);

    await tester.pump(const Duration(milliseconds: 100));
    expect(content.opacity.value, 1);
    expect(surface.scale.value, 1);
  });

  testWidgets('close reverses the entrance before clearing the reply', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      harness(
        child: ReplyComposerPreview(
          quotedText: 'Dismiss me',
          onClose: () => closed = true,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 120));
    final content = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('reply-preview-content-opacity')),
    );
    final opacityBeforeClose = content.opacity.value;

    await tester.tap(find.byTooltip('Cancel reply'));
    expect(closed, isFalse);

    // The first frame establishes the reverse ticker's epoch; the following
    // frame advances it, matching how the engine schedules a newly reversed
    // controller on device.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final reversingContent = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('reply-preview-content-opacity')),
    );
    expect(reversingContent.opacity.value, lessThan(opacityBeforeClose));
    expect(closed, isFalse);

    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });

  testWidgets('reduce motion dismisses immediately', (tester) async {
    var closeCount = 0;
    await tester.pumpWidget(
      harness(
        reduceMotion: true,
        child: ReplyComposerPreview(
          quotedText: 'Dismiss without motion',
          onClose: () => closeCount++,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.tap(find.byTooltip('Cancel reply'));
    expect(closeCount, 1);
  });
}
