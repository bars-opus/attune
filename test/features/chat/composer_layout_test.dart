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
  testWidgets('camera sits outside the pill on the left, attach on the right', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final field = _pill(tester);
    final camera = tester.getCenter(find.byIcon(Icons.camera_alt_rounded));
    final attach = tester.getCenter(
      find.byIcon(Icons.add_circle_outline_rounded),
    );

    expect(
      camera.dx,
      lessThan(field.left),
      reason: 'the camera is a satellite left of the pill, not inside it',
    );
    expect(
      attach.dx,
      greaterThan(field.right),
      reason: 'attach is a satellite right of the pill, not inside it',
    );
  });

  testWidgets('mic and games sit inside the pill, mic to the left of games', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final field = _pill(tester);
    final mic = tester.getCenter(find.byIcon(Icons.mic_none_rounded));
    final games = tester.getCenter(find.byIcon(Icons.sports_esports_outlined));

    expect(mic.dx, greaterThan(field.left));
    expect(
      mic.dx,
      lessThan(field.right),
      reason: 'the mic lives inside the pill',
    );
    expect(
      games.dx,
      lessThan(field.right),
      reason: 'games lives inside the pill',
    );
    expect(
      mic.dx,
      lessThan(games.dx),
      reason: 'the mic is the left of the two in-pill icons',
    );
  });

  testWidgets('the camera carries no primary fill', (tester) async {
    // In the reference the camera sits on the same neutral ground as the
    // attach button, not a primary-filled chip. It DOES have a ground --
    // the white circle -- so the assertion is that it matches attach,
    // rather than that it has no Container at all.
    await tester.pumpWidget(_harness());

    Color? groundOf(IconData icon) {
      final containers = tester.widgetList<Container>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)),
      );
      for (final c in containers) {
        final d = c.decoration;
        if (d is BoxDecoration && d.shape == BoxShape.circle) return d.color;
      }
      return null;
    }

    final cameraGround = groundOf(Icons.camera_alt_rounded);
    expect(cameraGround, isNotNull, reason: 'the camera has a circular ground');
    expect(
      cameraGround,
      groundOf(Icons.add_circle_outline_rounded),
      reason: 'camera and attach are the same kind of button',
    );

    final primary =
        Theme.of(
          tester.element(find.byType(ChatTextField)),
        ).colorScheme.primary;
    expect(
      cameraGround,
      isNot(primary),
      reason: 'the primary-filled chip is gone',
    );
  });
}
