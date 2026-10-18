// Spec 5 (research 06 §3 F9 (3)): the attachment result is about you. It
// carries the instrument caveat, it is never shared, and a partner cannot
// open one.
import 'dart:io';

import 'package:attune/features/profile/widgets/know_yourself_section.dart';
import 'package:attune/features/quiz/domain/models/attachment_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/screens/partner_quiz_result_screen.dart';
import 'package:attune/features/quiz/presentation/screens/quiz_result_screen.dart';
import 'package:attune/features/quiz/presentation/widgets/share_quiz_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

const _caveat =
    "Written for a general population; if you're autistic or ADHD some "
    'items may not fit.';

final _result = AttachmentResult(
  anxietyScore: 2,
  avoidanceScore: 2,
  resultType: 'secure',
  displayName: 'Secure',
  poeticDescription: 'Steady.',
  practiceBullets: ['Keep checking in.'],
  securePercentage: 70,
  anxiousPercentage: 10,
  avoidantPercentage: 10,
  fearfulPercentage: 10,
);

Widget _app(Widget home, List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: home),
  ),
);

void main() {
  testWidgets('the result carries the caveat and no share, even in couples mode', (t) async {
    t.view.physicalSize = const Size(1170, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _app(QuizResultScreen(result: _result, quizType: 'attachment'), [
        userRelationshipModeProvider.overrideWith((ref) async => 'couples'),
      ]),
    );
    await t.pump(const Duration(milliseconds: 2000));
    await t.pump(const Duration(milliseconds: 1100));
    expect(find.text(_caveat), findsOneWidget);
    expect(find.byType(ShareQuizButton), findsNothing);
    expect(find.text('Retake quiz'), findsOneWidget);
  });

  testWidgets("a partner's attachment result never opens", (t) async {
    var read = false;
    await t.pumpWidget(
      _app(const PartnerQuizResultScreen(quizType: 'attachment', partnerId: 'p'), [
        partnerQuizResultProvider.overrideWith((ref, params) async {
          read = true;
          return null;
        }),
      ]),
    );
    await t.pump();
    expect(find.text('Attachment results stay with the person who took them.'), findsOneWidget);
    expect(read, isFalse);
  });

  test('sharing an attachment result is refused before anything is sent', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await expectLater(
      c.read(shareQuizResultProvider((quizType: 'attachment')).future),
      throwsA(isA<UnsupportedError>()),
    );
  });

  testWidgets('the Know-yourself attachment sheet carries the caveat too (final review I-3)', (t) async {
    await t.pumpWidget(
      _app(const Scaffold(body: SingleChildScrollView(child: KnowYourselfSection())), [
        quizClinicalSignoffProvider.overrideWith((ref) async => false),
        userQuizzesStatusProvider.overrideWith((ref) async => {
          'attachment': QuizCompletionStatus(completed: true, displayName: 'Secure', result: _result),
        }),
      ]),
    );
    await t.pump();
    await t.pump();
    await t.tap(find.text('Attachment style'));
    await t.pumpAndSettle();
    expect(find.text('Your attachment style'), findsOneWidget);
    expect(find.text(_caveat), findsOneWidget);
    expect(AttachmentResult.caveat, _caveat);
  });

  test('no code path builds a partner-facing attachment result (final review M-2)', () {
    final src = File('lib/features/quiz/presentation/providers/quiz_providers.dart').readAsStringSync();
    final at = src.indexOf('final partnerQuizResultProvider');
    final body = src.substring(at, src.indexOf('\n});\n', at));
    expect(body, isNot(contains("case 'attachment':")));
    expect(body, isNot(contains('SharedQuizResult.attachment(')));
  });

  test('a shared communication result is read from the shared response (final review, declined #1)', () {
    final src = File('lib/features/quiz/presentation/providers/quiz_providers.dart').readAsStringSync();
    final at = src.indexOf("    case 'communication':", src.indexOf('final partnerQuizResultProvider'));
    final body = src.substring(at, src.indexOf("    case 'conflict':", at));
    expect(body, contains(".from('quiz_responses')"));
    expect(body, isNot(contains(".from('psych_profiles')")));
    final save = src.substring(src.indexOf('final saveCommunicationQuizResultProvider'));
    final insert = save.substring(save.indexOf(".from('quiz_responses').insert({"));
    expect(insert.substring(0, insert.indexOf('});')), contains("'result_data'"));
  });
}
