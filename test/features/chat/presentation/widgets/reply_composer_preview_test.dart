import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/features/chat/presentation/widgets/reply_composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget harness(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    );
  }

  testWidgets('renders as an immediately settled flight destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'A message worth answering',
          onClose: () {},
        ),
      ),
    );

    expect(
      find.textContaining('Replying to you', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('A message worth answering', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reply-preview-surface-motion')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('reply-preview-content-opacity')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('reply-preview-accent-rail')),
      findsNothing,
    );
  });

  testWidgets('surface key measures the card inside its outer padding', (
    tester,
  ) async {
    final surfaceKey = GlobalKey();

    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          surfaceKey: surfaceKey,
          quotedText: 'Measured destination',
          onClose: () {},
        ),
      ),
    );

    final previewRect = tester.getRect(find.byType(ReplyComposerPreview));
    final surfaceRect = tester.getRect(find.byKey(surfaceKey));
    expect(surfaceRect.left, greaterThan(previewRect.left));
    expect(surfaceRect.right, lessThan(previewRect.right));
    expect(surfaceRect.bottom, previewRect.bottom);
  });

  testWidgets('close delegates cancellation to the screen flight owner', (
    tester,
  ) async {
    var closeCount = 0;
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Fly me back',
          onClose: () => closeCount++,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Cancel reply'));
    expect(closeCount, 1);
  });

  testWidgets('uses the sender bubble surface when replying to your message', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Outgoing bubble',
          isMine: true,
          onClose: () {},
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, ThemeData.light().chatColors.senderBubble);
  });

  testWidgets('keeps the neutral surface when replying to their message', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(quotedText: 'Incoming bubble', onClose: () {}),
      ),
    );

    final context = tester.element(find.byType(ReplyComposerPreview));
    final card = tester.widget<Card>(find.byType(Card));
    expect(card.color, Theme.of(context).colorScheme.surface);
  });

  testWidgets('can label partner replies by name', (tester) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Incoming bubble',
          replyingToLabel: 'James',
          onClose: () {},
        ),
      ),
    );

    expect(
      find.textContaining('Replying to James', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('shows a game icon beside a game reply preview', (tester) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Snakes and Ladders',
          kind: ReplyPreviewKind.game,
          onClose: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.sports_esports_outlined), findsOneWidget);
    expect(
      find.textContaining('Snakes and Ladders', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('shows media type icons beside media reply previews', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        Column(
          children: [
            ReplyComposerPreview(
              quotedText: 'Photo',
              kind: ReplyPreviewKind.image,
              onClose: () {},
            ),
            ReplyComposerPreview(
              quotedText: 'Video',
              kind: ReplyPreviewKind.video,
              onClose: () {},
            ),
            ReplyComposerPreview(
              quotedText: 'Voice message',
              kind: ReplyPreviewKind.audio,
              onClose: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
  });

  testWidgets('shows the opened streak affordance in reply previews', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Opened',
          kind: ReplyPreviewKind.streakOpened,
          onClose: () {},
        ),
      ),
    );

    expect(find.byIcon(Icons.check_box_outline_blank_rounded), findsOneWidget);
    expect(find.textContaining('Opened', findRichText: true), findsOneWidget);
  });

  testWidgets('media reply icons use adaptive background ink', (tester) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Video',
          kind: ReplyPreviewKind.video,
          onClose: () {},
        ),
      ),
    );

    final context = tester.element(find.byType(ReplyComposerPreview));
    final icon = tester.widget<Icon>(find.byIcon(Icons.videocam_outlined));
    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.videocam_outlined),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, Theme.of(context).colorScheme.onBackground);
    expect(icon.color, Theme.of(context).colorScheme.background);
  });

  testWidgets('audio reply icon uses the voice accent instead of media ink', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        ReplyComposerPreview(
          quotedText: 'Voice message',
          kind: ReplyPreviewKind.audio,
          onClose: () {},
        ),
      ),
    );

    final context = tester.element(find.byType(ReplyComposerPreview));
    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.play_arrow_rounded),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration as BoxDecoration;

    expect(decoration.color, Theme.of(context).chatColors.voiceAccent);
  });
}
