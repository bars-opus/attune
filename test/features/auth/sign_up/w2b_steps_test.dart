// Spec 1 W2b (§2.3, §3.3 A1–A5, N1): what the step screens do beyond how
// they look (w2b_goldens_test.dart). Each screen meets the three
// accessibility guidelines; every submit runs once however fast it is
// pressed (busy only disables on the next frame); every failed submit is
// read out again; errors are the shared FlowErrorLine (ruling C5); A2's
// field order is whatever the flow passes in (the platform locale, never
// the app's language-only one) and its fields stack at large text; consent
// never animates.
import 'dart:async';

import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/birth_date_validator.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/birth_date_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/code_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/consent_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/name_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/no_account_step.dart';
import 'package:attune/features/auth/sign_up/presentation/steps/phone_step.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/one_time_code_field.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

final _now = DateTime.utc(2026, 10, 25, 12);
final _ghana = PhoneCountries.all.firstWhere((c) => c.isoCode == 'GH');

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

/// Taps [label] twice before any frame, as a fast double tap does.
Future<void> _doubleTap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  group('the three accessibility guidelines', () {
    final screens = <String, Widget Function()>{
      'A1 name': () => NameStep(onSubmit: (_) {}, onBack: () {}),
      'A2 date of birth':
          () => BirthDateStep(
            order: BirthDateOrder.dayMonthYear,
            todayUtc: _now,
            initialDate: DateTime.utc(1991, 11, 8),
            onSubmit: (_) {},
            onBack: () {},
          ),
      'A3 phone, with a send error':
          () => PhoneStep(
            initialCountry: _ghana,
            initialNational: '244123456',
            sendError: "We couldn't send a code. Try again or try WhatsApp.",
            onSend: (_, __) {},
            onBack: () {},
          ),
      'A4 code, with a wrong code':
          () => CodeStep(
            phoneE164: '+233244123456',
            lastSentAt: _now,
            sendCount: 2,
            now: () => _now,
            errorText: "That code didn't work. Check it and try again.",
            errorCount: 1,
            onCode: (_) {},
            onResend: () {},
            onChangeNumber: () {},
          ),
      'A4 code, ready to resend, accepted but unread':
          () => CodeStep(
            phoneE164: '+233244123456',
            lastSentAt: null,
            sendCount: 1,
            now: () => _now,
            onCode: (_) {},
            onResend: () {},
            onChangeNumber: () {},
            onRetry: () {},
          ),
      'A5 consent, with an error':
          () => ConsentStep(
            errorText: "We couldn't save that. Try again.",
            onAgree: () {},
            onNotNow: () {},
          ),
      'A5c updated terms':
          () =>
              ConsentStep(updatedTerms: true, onAgree: () {}, onNotNow: () {}),
      'N1 no account':
          () => NoAccountStep(onCreate: () {}, onOtherNumber: () {}),
      'Welcome back': () => const WelcomeBackStep(firstName: 'Esi'),
    };
    for (final MapEntry(key: name, value: screen) in screens.entries) {
      testWidgets(name, (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpFlowScreen(tester, screen);
        await expectFlowGuidelines(tester);
        semantics.dispose();
      });
    }
  });

  group('every submit runs once, however fast it is pressed', () {
    testWidgets('A1 Continue', (tester) async {
      final names = <String>[];
      var gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => NameStep(
          initialName: '  Ama   Owusu ',
          onSubmit: (name) {
            names.add(name);
            return gate.future;
          },
          onBack: () {},
        ),
      );
      await _doubleTap(tester, 'Continue');
      expect(names, ['Ama Owusu'], reason: 'normalised, and sent once');

      gate.complete();
      gate = Completer<void>();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(names, hasLength(2), reason: 'free again once it has finished');
    });

    testWidgets('A2 Continue', (tester) async {
      final dates = <DateTime>[];
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => BirthDateStep(
          order: BirthDateOrder.dayMonthYear,
          todayUtc: _now,
          initialDate: DateTime.utc(1991, 11, 8),
          onSubmit: (date) {
            dates.add(date);
            return gate.future;
          },
          onBack: () {},
        ),
      );
      await _doubleTap(tester, 'Continue');
      expect(dates, [DateTime.utc(1991, 11, 8)]);
      gate.complete();
    });

    testWidgets('A3 Text me a code', (tester) async {
      final sent = <(String, String)>[];
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          initialNational: '244123456',
          onSend: (e164, iso) {
            sent.add((e164, iso));
            return gate.future;
          },
          onBack: () {},
        ),
      );
      await _doubleTap(tester, 'Text me a code');
      expect(sent, [('+233244123456', 'GH')]);
      gate.complete();
    });

    testWidgets('A3 while the flow is busy, Done on the keyboard sends none', (
      tester,
    ) async {
      final sent = <String>[];
      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          initialNational: '244123456',
          busy: true,
          onSend: (e164, _) => sent.add(e164),
          onBack: () {},
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(sent, isEmpty);
    });

    testWidgets('A4 Send a new code and Try again', (tester) async {
      var resends = 0;
      var retries = 0;
      var gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => CodeStep(
          phoneE164: '+233244123456',
          lastSentAt: null,
          sendCount: 1,
          now: () => _now,
          onCode: (_) {},
          onResend: () {
            resends++;
            return gate.future;
          },
          onChangeNumber: () {},
          onRetry: () {
            retries++;
            return gate.future;
          },
        ),
      );
      // All before a frame: the other button is still live until then.
      await tester.tap(find.text('Send a new code'));
      await tester.tap(find.text('Try again'));
      await tester.tap(find.text('Send a new code'));
      await tester.pump();
      expect(resends, 1);
      expect(retries, 0, reason: 'nothing else starts while one runs');

      gate.complete();
      gate = Completer<void>();
      await tester.pumpAndSettle();
      await _doubleTap(tester, 'Try again');
      expect(retries, 1);
      gate.complete();
    });

    testWidgets('A4 a completed code is checked once', (tester) async {
      final codes = <String>[];
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => CodeStep(
          phoneE164: '+233244123456',
          lastSentAt: _now,
          sendCount: 1,
          now: () => _now,
          onCode: (code) {
            codes.add(code);
            return gate.future;
          },
          onResend: () {},
          onChangeNumber: () {},
        ),
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(codes, ['123456']);
      gate.complete();
    });

    testWidgets('A5 Agree and continue, then Not now', (tester) async {
      var agreed = 0;
      var notNow = 0;
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => ConsentStep(
          onAgree: () {
            agreed++;
            return gate.future;
          },
          onNotNow: () => notNow++,
        ),
      );
      // All before a frame: the other button is still live until then.
      await tester.tap(find.text('Agree and continue'));
      await tester.tap(find.text('Not now'));
      await tester.tap(find.text('Agree and continue'));
      await tester.pump();
      expect((agreed, notNow), (1, 0));
      gate.complete();
    });

    testWidgets('N1 Create an account and Use a different number', (
      tester,
    ) async {
      var created = 0;
      var other = 0;
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => NoAccountStep(
          onCreate: () {
            created++;
            return gate.future;
          },
          onOtherNumber: () => other++,
        ),
      );
      // All before a frame: the other button is still live until then.
      await tester.tap(find.text('Create an account'));
      await tester.tap(find.text('Use a different number'));
      await tester.tap(find.text('Create an account'));
      await tester.pump();
      expect((created, other), (1, 0));
      gate.complete();
    });
  });

  group('every failed submit is read out again', () {
    testWidgets('A1, an empty name', (tester) async {
      final said = _announcements(tester);
      await pumpFlowScreen(
        tester,
        () => NameStep(onSubmit: (_) {}, onBack: () {}),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(
        said.where((m) => m == 'Add a name with at least one letter.'),
        hasLength(2),
      );
    });

    testWidgets('A3, a number too short', (tester) async {
      final said = _announcements(tester);
      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          initialNational: '12',
          onSend: (_, __) {},
          onBack: () {},
        ),
      );
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Text me a code'));
        await tester.pumpAndSettle();
      }
      expect(
        said.where((m) => m == 'Check the number. It looks too short.'),
        hasLength(2),
      );
    });

    testWidgets('A2, a day out of range', (tester) async {
      final said = _announcements(tester);
      await pumpFlowScreen(
        tester,
        () => BirthDateStep(
          order: BirthDateOrder.dayMonthYear,
          todayUtc: _now,
          onSubmit: (_) {},
          onBack: () {},
        ),
      );
      await tester.enterText(find.byType(TextField).first, '32');
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(
        said.where((m) => m == 'Day must be between 1 and 31.'),
        hasLength(2),
      );
    });
  });

  group('errors are the shared error line (ruling C5)', () {
    Finder errorLine(String text) => find.ancestor(
      of: find.text(text),
      matching: find.byType(FlowErrorLine),
    );

    testWidgets('A2', (tester) async {
      await pumpFlowScreen(
        tester,
        () => BirthDateStep(
          order: BirthDateOrder.dayMonthYear,
          todayUtc: _now,
          onSubmit: (_) {},
          onBack: () {},
        ),
      );
      await tester.enterText(find.byType(TextField).first, '32');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(errorLine('Day must be between 1 and 31.'), findsOneWidget);
    });

    testWidgets('A3', (tester) async {
      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          sendError: "We couldn't send a code. Try again or try WhatsApp.",
          onSend: (_, __) {},
          onBack: () {},
        ),
      );
      expect(
        errorLine("We couldn't send a code. Try again or try WhatsApp."),
        findsOneWidget,
      );
    });

    testWidgets('A4', (tester) async {
      await pumpFlowScreen(
        tester,
        () => CodeStep(
          phoneE164: '+233244123456',
          lastSentAt: _now,
          sendCount: 1,
          now: () => _now,
          errorText: "That code didn't work. Check it and try again.",
          onCode: (_) {},
          onResend: () {},
          onChangeNumber: () {},
        ),
      );
      expect(
        errorLine("That code didn't work. Check it and try again."),
        findsOneWidget,
      );
    });

    testWidgets('A5, read out as it appears', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => ConsentStep(
          errorText: "We couldn't save that. Try again.",
          onAgree: () {},
          onNotNow: () {},
        ),
      );
      final line = errorLine("We couldn't save that. Try again.");
      expect(line, findsOneWidget);
      expect(tester.widget<FlowErrorLine>(line).liveRegion, isTrue);
      expect(
        tester.getSemantics(find.text("We couldn't save that. Try again.")),
        containsSemantics(isLiveRegion: true),
      );
      semantics.dispose();
    });
  });

  group('A2 date of birth', () {
    Widget step(BirthDateOrder order) => BirthDateStep(
      order: order,
      todayUtc: _now,
      initialDate: DateTime.utc(1991, 11, 8),
      onSubmit: (_) {},
      onBack: () {},
    );

    testWidgets(
      'the fields follow the order it is given, not the app language',
      (tester) async {
        // A Ghanaian phone: the flow passes day first (birthDateOrderFor
        // the platform locale). The step itself never looks it up.
        tester.platformDispatcher.localeTestValue = const Locale('en', 'GH');
        await pumpFlowScreen(tester, () => step(BirthDateOrder.monthDayYear));
        expect(
          tester.getTopLeft(find.text('Month')).dx,
          lessThan(tester.getTopLeft(find.text('Day')).dx),
        );

        await pumpFlowScreen(tester, () => step(BirthDateOrder.dayMonthYear));
        expect(
          tester.getTopLeft(find.text('Day')).dx,
          lessThan(tester.getTopLeft(find.text('Month')).dx),
        );
      },
    );

    testWidgets('says the date and the age, joined by MyDateFormat', (
      tester,
    ) async {
      await pumpFlowScreen(tester, () => step(BirthDateOrder.dayMonthYear));
      expect(
        find.text('Friday, November 8, 1991 - that makes you 34.'),
        findsOneWidget,
      );
    });

    for (final (scale, stacked) in [(1.3, false), (2.0, true)]) {
      testWidgets(
        'at text size $scale the fields ${stacked ? 'stack' : 'share a row'}',
        (tester) async {
          await pumpFlowScreen(
            tester,
            () => step(BirthDateOrder.dayMonthYear),
            textScale: scale,
          );
          // Day, month, year: the fields in reading order.
          final fields = find.byType(TextField);
          final day = tester.getTopLeft(fields.at(0));
          final month = tester.getTopLeft(fields.at(1));
          final year = tester.getTopLeft(fields.at(2));
          if (stacked) {
            expect(month.dy, greaterThan(day.dy));
            expect(year.dy, greaterThan(month.dy));
          } else {
            expect(month.dy, day.dy);
            expect(year.dy, day.dy);
          }
        },
      );
    }
  });

  testWidgets('A4 the code field takes focus back once it is enabled again', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    Widget field({required bool enabled}) => MaterialApp(
      home: Scaffold(
        body: OneTimeCodeField(
          controller: controller,
          semanticsLabel: 'Verification code, 6 digits',
          onCompleted: (_) {},
          enabled: enabled,
        ),
      ),
    );
    bool focused() =>
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus;

    await tester.pumpWidget(field(enabled: true));
    await tester.pump();
    expect(focused(), isTrue);
    // Checking a code (or sending a new one) disables the field.
    await tester.pumpWidget(field(enabled: false));
    await tester.pump();
    expect(focused(), isFalse);
    await tester.pumpWidget(field(enabled: true));
    await tester.pump();
    expect(
      focused(),
      isTrue,
      reason: 'the keyboard comes back for the next try',
    );
  });

  testWidgets('A3 with no country to start from opens the picker', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => PhoneStep(initialCountry: null, onSend: (_, __) {}, onBack: () {}),
    );
    expect(find.byType(PhoneCountryPickerSheet), findsOneWidget);
  });

  testWidgets(
    'A5 links: on screen they meet the guidelines, and each opens its document',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => ConsentStep(onAgree: () {}, onNotNow: () {}),
      );
      // Below the fold in the test font, where the check above can't see
      // them.
      await tester.ensureVisible(find.text('More about AI in Attune'));
      await tester.pumpAndSettle();
      await expectFlowGuidelines(tester);

      for (final (link, title) in [
        ('Terms of use', 'Terms of Service'),
        ('Privacy policy', 'Privacy Policy'),
      ]) {
        await tester.tap(find.text(link));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('I Agree'), findsNothing, reason: 'read only');
        Navigator.of(tester.element(find.text(title))).pop();
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('More about AI in Attune'));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentationTabView), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'A3 the country button is one a screen reader can press (review B4 I-1)',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          onSend: (_, __) {},
          onBack: () {},
        ),
      );
      final button = find.byType(OutlinedButton);
      expect(
        tester.getSemantics(button),
        containsSemantics(
          label: 'Country, Ghana, +233',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );
      // What TalkBack's double tap and VoiceOver's activate send.
      tester.semantics.tap(find.semantics.byLabel('Country, Ghana, +233'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneCountryPickerSheet), findsOneWidget);

      await pumpFlowScreen(
        tester,
        () => PhoneStep(
          initialCountry: _ghana,
          busy: true,
          onSend: (_, __) {},
          onBack: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(OutlinedButton)),
        containsSemantics(
          label: 'Country, Ghana, +233',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      semantics.dispose();
    },
  );

  group('progress shows on the button that was pressed (review B4 I-3)', () {
    final ring = find.byType(CircularProgressIndicator);
    Finder inside(Type button) =>
        find.descendant(of: find.byType(button), matching: ring);

    for (final (name, screen, primary, secondary) in <
      (String, Widget Function(Future<void> Function() slow), String, String)
    >[
      (
        'A5',
        (slow) => ConsentStep(onAgree: () {}, onNotNow: slow),
        'Agree and continue',
        'Not now',
      ),
      (
        'N1',
        (slow) => NoAccountStep(onCreate: () {}, onOtherNumber: slow),
        'Create an account',
        'Use a different number',
      ),
    ]) {
      testWidgets('$name: "$secondary" shows its own, read by its own name', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final gate = Completer<void>();
        await pumpFlowScreen(tester, () => screen(() => gate.future));
        await tester.tap(find.text(secondary));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));

        expect(inside(FilledButton), findsNothing);
        expect(find.text(primary), findsOneWidget);
        expect(inside(OutlinedButton), findsOneWidget);
        expect(
          tester.getSemantics(inside(OutlinedButton)),
          containsSemantics(label: secondary),
        );
        gate.complete();
        await tester.pumpAndSettle();
        expect(ring, findsNothing);
        semantics.dispose();
      });
    }

    testWidgets('A5: "Agree and continue" shows its own', (tester) async {
      final gate = Completer<void>();
      await pumpFlowScreen(
        tester,
        () => ConsentStep(onAgree: () => gate.future, onNotNow: () {}),
      );
      await tester.tap(find.text('Agree and continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(inside(FilledButton), findsOneWidget);
      expect(inside(OutlinedButton), findsNothing);
      expect(find.text('Not now'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  testWidgets(
    'an action that throws is reported, never lost, and the step can be '
    'used again (review B4 M-2)',
    (tester) async {
      final reported = <FlutterErrorDetails>[];
      var calls = 0;
      await pumpFlowScreen(
        tester,
        () => NameStep(
          initialName: 'Ama',
          onSubmit: (_) async {
            calls++;
            await Future<void>.delayed(Duration.zero);
            throw StateError('offline');
          },
          onBack: () {},
        ),
      );
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      try {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(calls, 1);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(reported.single.library, 'sign-up');

      FlutterError.onError = reported.add;
      try {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previous;
      }
      expect(calls, 2, reason: 'free again after the failure');
    },
  );

  testWidgets('Welcome back reads its greeting out (review B4 M-5)', (
    tester,
  ) async {
    final said = _announcements(tester);
    await pumpFlowScreen(tester, () => const WelcomeBackStep(firstName: 'Esi'));
    expect(said, ['Welcome back, Esi.']);
  });

  testWidgets('A5 starts no animation on its first frame (spec §2.2)', (
    tester,
  ) async {
    await pumpFlowScreen(tester, () => const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConsentStep(onAgree: () {}, onNotNow: () {}),
      ),
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
