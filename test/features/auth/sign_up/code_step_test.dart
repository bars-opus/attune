// Spec 1 W2b (§3.3 A4): the code step. Only a wrong code shakes the boxes;
// a send failure, a rate limit or a check that couldn't run is a notice
// under the resend row, read out, with the boxes still and not red (review
// B4 I-2). "Change it" waits for a check in progress (M-1). A code that
// arrives while the step is busy is kept and checked once it is free (M-4).
// Progress shows on the button that was pressed (I-3).
import 'dart:async';

import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
const _wrong = "That code didn't work. Check it and try again.";
const _expired = 'That code has expired. Send a new one.';
const _tooMany = 'Too many codes. Try again in 5 minutes.';

/// What the flow drives A4 with, changed the way the flow changes it.
class _Flow extends ChangeNotifier {
  String? errorText;
  int errorCount = 0;
  int shakeCount = 0;
  String? noticeText;
  int noticeCount = 0;
  bool busy = false;
  int sendCount = 1;
  DateTime? lastSentAt;
  String? autofillCode;

  void update(void Function(_Flow flow) change) {
    change(this);
    notifyListeners();
  }
}

Widget Function() _host(
  _Flow flow, {
  FutureOr<void> Function(String code)? onCode,
  FutureOr<void> Function()? onResend,
  FutureOr<void> Function()? onChangeNumber,
  FutureOr<void> Function()? onRetry,
}) =>
    () => ListenableBuilder(
      listenable: flow,
      builder:
          (_, __) => CodeStep(
            phoneE164: '+233244123456',
            lastSentAt: flow.lastSentAt,
            sendCount: flow.sendCount,
            now: () => _now,
            errorText: flow.errorText,
            errorCount: flow.errorCount,
            shakeCount: flow.shakeCount,
            noticeText: flow.noticeText,
            noticeCount: flow.noticeCount,
            busy: flow.busy,
            autofillCode: flow.autofillCode,
            onCode: onCode ?? (_) {},
            onResend: onResend ?? () {},
            onChangeNumber: onChangeNumber ?? () {},
            onRetry: onRetry,
          ),
    );

/// What a screen reader was asked to read out, in order.
List<String> _announcements(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final said = <String>[];
  messenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final event = message as Map<Object?, Object?>;
      if (event['type'] == 'announce') {
        said.add((event['data'] as Map<Object?, Object?>)['message'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      null,
    ),
  );
  return said;
}

/// How far the six boxes are moved sideways right now.
double _shake(WidgetTester tester) {
  final boxes =
      find
          .descendant(
            of: find.byType(OneTimeCodeField),
            matching: find.byType(Stack),
          )
          .first;
  return tester
      .widget<Transform>(
        find.ancestor(of: boxes, matching: find.byType(Transform)).first,
      )
      .transform
      .getTranslation()
      .x;
}

/// The colours of the six boxes' borders.
List<Color> _boxBorders(WidgetTester tester) => [
  for (final container in tester.widgetList<Container>(
    find.descendant(
      of: find.byType(OneTimeCodeField),
      matching: find.byType(Container),
    ),
  ))
    if (container.decoration case BoxDecoration(border: final Border border))
      border.top.color,
];

Color _errorColour(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(OneTimeCodeField))).colorScheme.error;

Finder _errorLine(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(FlowErrorLine));

void main() {
  group('only a wrong code shakes (review B4 I-2)', () {
    testWidgets('a wrong code: read out, red boxes, and they shake', (
      tester,
    ) async {
      final said = _announcements(tester);
      final flow = _Flow();
      await pumpFlowScreen(tester, _host(flow));
      flow.update((f) {
        f.errorText = _wrong;
        f.errorCount++;
        f.shakeCount++;
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(_shake(tester), isNot(0));
      await tester.pumpAndSettle();
      expect(said, [_wrong]);
      expect(_boxBorders(tester), hasLength(6));
      expect(_boxBorders(tester), everyElement(_errorColour(tester)));
      expect(_errorLine(_wrong), findsOneWidget);
    });

    testWidgets('an expired code: read out and red, but still', (tester) async {
      final said = _announcements(tester);
      final flow = _Flow();
      await pumpFlowScreen(tester, _host(flow));
      flow.update((f) {
        f.errorText = _expired;
        f.errorCount++;
      });
      await tester.pump();
      for (final ms in [30, 60, 120]) {
        await tester.pump(Duration(milliseconds: ms));
        expect(_shake(tester), 0, reason: 'still at $ms ms');
      }
      expect(said, [_expired]);
      expect(_boxBorders(tester), everyElement(_errorColour(tester)));
    });

    testWidgets(
      'a rate limit is a notice: read out each time, under the resend row, '
      'boxes still and not red',
      (tester) async {
        final said = _announcements(tester);
        final flow = _Flow();
        await pumpFlowScreen(tester, _host(flow));
        flow.update((f) {
          f.noticeText = _tooMany;
          f.noticeCount++;
        });
        await tester.pump();
        for (final ms in [30, 60, 120]) {
          await tester.pump(Duration(milliseconds: ms));
          expect(_shake(tester), 0, reason: 'still at $ms ms');
        }
        await tester.pumpAndSettle();
        expect(said, [_tooMany]);
        expect(_errorLine(_tooMany), findsOneWidget);
        expect(_boxBorders(tester), hasLength(6));
        expect(
          _boxBorders(tester),
          everyElement(isNot(_errorColour(tester))),
          reason: 'nothing is wrong with the code',
        );
        expect(
          tester.getTopLeft(find.text(_tooMany)).dy,
          greaterThan(tester.getTopLeft(find.text('Send a new code')).dy),
        );

        // The same notice again (a second failed send) is read out again.
        flow.update((f) => f.noticeCount++);
        await tester.pumpAndSettle();
        expect(said, [_tooMany, _tooMany]);
      },
    );
  });

  testWidgets('"Change it" and Back wait for a check in progress (M-1)', (
    tester,
  ) async {
    final codes = <String>[];
    var changes = 0;
    final check = Completer<void>();
    final change = Completer<void>();
    final flow = _Flow();
    await pumpFlowScreen(
      tester,
      _host(
        flow,
        onCode: (code) {
          codes.add(code);
          return check.future;
        },
        onChangeNumber: () {
          changes++;
          return change.future;
        },
      ),
    );
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(codes, ['123456']);

    await tester.tap(find.text('Wrong number? Change it'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(changes, 0, reason: 'a code is being checked');

    check.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wrong number? Change it'));
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(changes, 1, reason: 'once, however fast it is pressed');
    change.complete();
  });

  testWidgets(
    'a code that arrives while a new one is sent is kept and checked once '
    'the step is free (M-4)',
    (tester) async {
      final codes = <String>[];
      final flow = _Flow()..lastSentAt = _now;
      await pumpFlowScreen(tester, _host(flow, onCode: codes.add));

      // A resend is in flight when the SMS listener reads the new code.
      flow.update((f) => f.busy = true);
      await tester.pump();
      flow.update((f) => f.autofillCode = '654321');
      await tester.pump();
      await tester.pump();
      expect(codes, isEmpty, reason: 'not while the step is busy');

      // The resend's reply: a new send, and the step is free.
      flow.update((f) {
        f.sendCount = 2;
        f.busy = false;
      });
      await tester.pump();
      await tester.pump();
      expect(codes, ['654321']);
      for (final digit in ['6', '5', '4', '3', '2', '1']) {
        expect(find.text(digit), findsOneWidget, reason: 'still in the boxes');
      }

      await tester.pumpAndSettle();
      expect(codes, ['654321'], reason: 'checked once');
    },
  );

  testWidgets(
    'a resend shows no progress on Try again; Try again shows its own (I-3)',
    (tester) async {
      final resend = Completer<void>();
      final retry = Completer<void>();
      final flow = _Flow();
      await pumpFlowScreen(
        tester,
        _host(flow, onResend: () => resend.future, onRetry: () => retry.future),
      );
      final ring = find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      );

      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(ring, findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      resend.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(ring, findsOneWidget);
      retry.complete();
      await tester.pumpAndSettle();
    },
  );

  group('batch 4 N-1: one check per distinct code', () {
    /// A check that takes 300 ms and finds the code wrong.
    FutureOr<void> Function(String) failingCheck(
      _Flow flow,
      List<String> codes,
    ) => (code) async {
      codes.add(code);
      flow.update((f) => f.busy = true);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      flow.update((f) {
        f.busy = false;
        f.errorText = _wrong;
        f.errorCount++;
        f.shakeCount++;
      });
    };

    testWidgets(
      'a code autofilled while a wrong one is checked, and wrong too, is '
      'checked once: [A, B], never [A, B, B]',
      (tester) async {
        final codes = <String>[];
        final flow = _Flow();
        await pumpFlowScreen(
          tester,
          _host(flow, onCode: failingCheck(flow, codes)),
        );
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump(const Duration(milliseconds: 100));
        // B arrives from the SMS listener while A is checked.
        flow.update((f) => f.autofillCode = '654321');
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(codes, ['123456', '654321']);
      },
    );

    testWidgets('the same code is checked again once the field has changed', (
      tester,
    ) async {
      final codes = <String>[];
      final flow = _Flow();
      await pumpFlowScreen(
        tester,
        _host(flow, onCode: failingCheck(flow, codes)),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(codes, ['123456']);
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(codes, ['123456', '123456']);
    });
  });

  group('autofill: six ASCII digits or nothing (review B8 m-4)', () {
    for (final code in [
      '12345',
      '1234567',
      '12345a',
      '\u0661\u0662\u0663\u0664\u0665\u0666',
    ]) {
      testWidgets('"$code" fills nothing and checks nothing', (tester) async {
        final codes = <String>[];
        final flow = _Flow();
        await pumpFlowScreen(tester, _host(flow, onCode: codes.add));
        flow.update((f) => f.autofillCode = code);
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, isEmpty);
        expect(codes, isEmpty);
      });
    }

    testWidgets('"123456" fills the boxes and is checked', (tester) async {
      final codes = <String>[];
      final flow = _Flow();
      await pumpFlowScreen(tester, _host(flow, onCode: codes.add));
      flow.update((f) => f.autofillCode = '123456');
      await tester.pumpAndSettle();
      expect(codes, ['123456']);
    });
  });

  group('W2c: the other channels', () {
    CodeStep step({
      int sendCount = 3,
      String lastChannel = 'sms',
      FutureOr<void> Function()? onTryWhatsApp,
      FutureOr<void> Function()? onCallMe,
    }) => CodeStep(
      phoneE164: '+233244123456',
      lastSentAt: _now.subtract(const Duration(minutes: 3)),
      sendCount: sendCount,
      now: () => _now,
      lastChannel: lastChannel,
      onCode: (_) {},
      onResend: () {},
      onChangeNumber: () {},
      onTryWhatsApp: onTryWhatsApp,
      onCallMe: onCallMe,
    );

    testWidgets('only after the second resend, and each only when given', (
      tester,
    ) async {
      await pumpFlowScreen(
        tester,
        () => step(sendCount: 2, onTryWhatsApp: () {}, onCallMe: () {}),
      );
      expect(find.text('Try WhatsApp'), findsNothing);
      expect(find.text('Call me with the code'), findsNothing);

      await pumpFlowScreen(tester, () => step(onTryWhatsApp: () {}));
      expect(find.text('Try WhatsApp'), findsOneWidget);
      expect(find.text('Call me with the code'), findsNothing);
      expect(find.textContaining("We're calling"), findsNothing);
    });

    testWidgets('"Try WhatsApp" runs once however fast it is pressed', (
      tester,
    ) async {
      var tries = 0;
      final send = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => step(
          onTryWhatsApp: () {
            tries++;
            return send.future;
          },
        ),
      );
      await tester.tap(find.text('Try WhatsApp'));
      await tester.tap(find.text('Try WhatsApp'));
      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      expect(tries, 1);
      send.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the call plumbing (unused in W2): the link when given, and '
        'the calling line for a voice code', (tester) async {
      await pumpFlowScreen(
        tester,
        () => step(lastChannel: 'voice', onTryWhatsApp: () {}, onCallMe: () {}),
      );
      expect(find.text('Call me with the code'), findsOneWidget);
      expect(
        find.text(
          "We're calling +233 24 412 3456 now. The code is read out twice.",
        ),
        findsOneWidget,
      );
    });
  });
}
