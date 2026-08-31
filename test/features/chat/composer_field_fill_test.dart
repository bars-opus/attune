import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

Widget _harness() => withScreenUtil(
  MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: ChatTextField(
          controller: TextEditingController(),
          onSend: () {},
          showVoiceMessage: true,
          showGames: true,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the field draws no fill of its own inside the pill', (
    tester,
  ) async {
    // The app-wide InputDecorationTheme sets filled: true with a surface
    // colour. The composer overrode only the BORDERS, so a square-cornered
    // filled rectangle sat inside the rounded pill and its corners showed
    // past the curve at the left edge.
    //
    // The pill already paints the background; the field must not paint a
    // second one.
    await tester.pumpWidget(_harness());

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;

    expect(
      decoration.filled,
      isFalse,
      reason: 'the pill owns the background, not the field',
    );
  });
}
