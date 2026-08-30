import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Widget _harness({String text = ''}) => withScreenUtil(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ChatTextField(
          controller: TextEditingController(text: text),
          onSend: () {},
          showVoiceMessage: true,
          showGames: true,
          showCaptureVideo: true,
          onCaptureVideo: () {},
          showAttachImage: true,
          onAttachImage: () {},
          onAttachFile: () {},
        ),
      ),
    ),
  ),
);

/// The pill's own bounds. Deliberately NOT the TextField's: the field
/// shrinks to fit around whatever icons share its row, so its edges move
/// with them and an inside/outside assertion against it always passes.
Rect _pill(WidgetTester tester) =>
    tester.getRect(find.byKey(const ValueKey('composer-pill')));

void main() {
  testWidgets('camera sits left of the pill and microphone sits right', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final field = _pill(tester);
    final camera = tester.getCenter(find.byIcon(Icons.photo_camera_outlined));
    final mic = tester.getCenter(find.byIcon(Icons.mic_none_rounded));

    expect(
      camera.dx,
      lessThan(field.left),
      reason: 'camera is the satellite left of the message pill',
    );
    expect(
      mic.dx,
      greaterThan(field.right),
      reason: 'microphone is the satellite right of the message pill',
    );
  });

  testWidgets(
    'games and attachments stay inside the pill while microphone stays outside',
    (tester) async {
      await tester.pumpWidget(_harness());

      final field = _pill(tester);
      final mic = tester.getCenter(find.byIcon(Icons.mic_none_rounded));
      final games = tester.getCenter(
        find.byIcon(Icons.sports_esports_outlined),
      );
      final attach = tester.getCenter(find.byIcon(Icons.attach_file_rounded));

      expect(mic.dx, greaterThan(field.right));
      expect(
        games.dx,
        lessThan(field.right),
        reason: 'games lives inside the pill',
      );
      expect(games.dx, greaterThan(field.left));
      expect(
        attach.dx,
        lessThan(field.right),
        reason: 'attachments live inside the pill',
      );
      expect(attach.dx, greaterThan(field.left));
    },
  );

  testWidgets('both outer actions use circular material surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    for (final icon in [Icons.photo_camera_outlined, Icons.mic_none_rounded]) {
      final grounds = tester.widgetList<Material>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Material)),
      );

      expect(
        grounds.any((material) => material.shape is CircleBorder),
        isTrue,
        reason: '$icon should sit on a circular surface',
      );
    }
  });

  testWidgets('message pill uses the same faint lift as chat bubbles', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final pill = tester.widget<Container>(
      find.byKey(const ValueKey('composer-pill')),
    );
    final decoration = pill.decoration;

    expect(decoration, isA<BoxDecoration>());
    expect((decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });
}
