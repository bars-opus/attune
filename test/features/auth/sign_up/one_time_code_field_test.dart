// Spec 1 W2b (§3.3 A4): one field, six boxes, autofill, digits only.
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(
  TextEditingController controller,
  List<String> completed, {
  String? error,
  int errorCount = 0,
  int shakeCount = 0,
  bool reduceMotion = false,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: OneTimeCodeField(
          controller: controller,
          semanticsLabel: 'Verification code, 6 digits',
          onCompleted: completed.add,
          errorText: error,
          errorCount: errorCount,
          shakeCount: shakeCount,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('one text field, labelled, asking for a one-time code', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(TextEditingController(), []));
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, [AutofillHints.oneTimeCode]);
    expect(field.keyboardType, TextInputType.number);
    expect(
      find.bySemanticsLabel('Verification code, 6 digits'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'a pasted or autofilled code fills all six boxes and completes once',
    (tester) async {
      final controller = TextEditingController();
      final completed = <String>[];
      await tester.pumpWidget(_host(controller, completed));
      await tester.enterText(find.byType(TextField), '12a34 5678');
      await tester.pump();
      expect(controller.text, '123456', reason: 'digits only, six at most');
      expect(completed, ['123456']);
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        expect(find.text(digit), findsOneWidget);
      }
      controller.text = '123456';
      await tester.pump();
      expect(completed, ['123456'], reason: 'the same code is not sent twice');
    },
  );

  testWidgets(
    'a wrong code shakes twice and is announced; reduce motion keeps still',
    (tester) async {
      final controller = TextEditingController(text: '111111');
      await tester.pumpWidget(_host(controller, []));
      await tester.pumpWidget(
        _host(
          controller,
          [],
          error: "That code didn't work. Check it and try again.",
          errorCount: 1,
          shakeCount: 1,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      final moving = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(Stack).first,
              matching: find.byType(Transform),
            )
            .first,
      );
      expect(moving.transform.getTranslation().x, isNot(0));
      await tester.pumpAndSettle();
      expect(
        find.text("That code didn't work. Check it and try again."),
        findsOneWidget,
      );

      await tester.pumpWidget(_host(controller, [], reduceMotion: true));
      await tester.pumpWidget(
        _host(
          controller,
          [],
          error: 'x',
          errorCount: 2,
          shakeCount: 2,
          reduceMotion: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets('any other error is read out and shown, and the boxes keep still '
      '(review B4 I-2: only a wrong code shakes)', (tester) async {
    final controller = TextEditingController(text: '111111');
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final event = message as Map<Object?, Object?>;
        if (event['type'] == 'announce') {
          said.add(
            (event['data'] as Map<Object?, Object?>)['message'] as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    await tester.pumpWidget(_host(controller, []));
    await tester.pumpWidget(
      _host(
        controller,
        [],
        error: 'That code has expired. Send a new one.',
        errorCount: 1,
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.binding.transientCallbackCount, 0, reason: 'no shake');
    expect(said, ['That code has expired. Send a new one.']);
    expect(find.text('That code has expired. Send a new one.'), findsOneWidget);
  });
}
