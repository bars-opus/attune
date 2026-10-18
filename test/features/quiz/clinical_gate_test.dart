// Spec 5 (R5-6, R5-7): the communication and conflict quizzes wait for
// clinical sign-off (quiz_clinical_signoff, default off); "Know yourself"
// sits on the person's own profile only.
import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/profile/widgets/know_yourself_section.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:attune/features/quiz/presentation/widgets/clinical_quiz_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home, {required bool signedOff, bool scroll = true}) => ProviderScope(
  overrides: [
    quizClinicalSignoffProvider.overrideWith((ref) async => signedOff),
    userQuizzesStatusProvider.overrideWith((ref) async => <String, QuizCompletionStatus>{}),
  ],
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: scroll ? Scaffold(body: SingleChildScrollView(child: home)) : home),
  ),
);

void main() {
  test('the flag key exists and defaults off', () {
    expect(ChatFeatureFlags.quizClinicalSignoff, 'quiz_clinical_signoff');
    expect(ChatFeatureFlags.defaultFor(ChatFeatureFlags.quizClinicalSignoff), isFalse);
  });

  testWidgets('before sign-off: communication and conflict say Coming soon', (t) async {
    await t.pumpWidget(_app(const KnowYourselfSection(), signedOff: false));
    await t.pump();
    await t.pump();
    expect(find.text('Coming soon'), findsNWidgets(2));
    expect(find.text('Start quiz'), findsOneWidget); // attachment
    expect(find.text('Add yours'), findsOneWidget); // what feels loving: an editor, not a quiz
    expect(find.text('What feels loving'), findsOneWidget);
  });

  testWidgets('after sign-off: all four can be started', (t) async {
    await t.pumpWidget(_app(const KnowYourselfSection(), signedOff: true));
    await t.pump();
    await t.pump();
    expect(find.text('Coming soon'), findsNothing);
    expect(find.text('Start quiz'), findsNWidgets(3));
    expect(find.text('Add yours'), findsOneWidget);
  });

  testWidgets('a gated route shows Coming soon, not the quiz', (t) async {
    await t.pumpWidget(_app(const ClinicalQuizGate(child: Text('the quiz')), signedOff: false, scroll: false));
    await t.pump();
    await t.pump();
    expect(find.text('the quiz'), findsNothing);
    expect(find.text('Coming soon'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // a fresh scope, not the old one
    await t.pumpWidget(_app(const ClinicalQuizGate(child: Text('the quiz')), signedOff: true, scroll: false));
    await t.pump();
    await t.pump();
    expect(find.text('the quiz'), findsOneWidget);
  });

  test('Know yourself is mounted on the own profile only', () {
    final src = File('lib/features/profile/widgets/profile_screen.dart').readAsStringSync();
    expect(src, contains('if (isAuthor)'));
    expect(RegExp(r'if \(isAuthor\)\s*Padding\([\s\S]{0,400}KnowYourselfSection\(\)').hasMatch(src), isTrue);
  });

  test('every clinical quiz route is gated', () {
    final src = File('lib/app/routing/app_router.dart').readAsStringSync();
    for (final name in ['communicationStyleQuiz', 'communicationStyleLoading', 'communicationStyleResult',
        'conflictStyleQuiz', 'conflictStyleLoading', 'conflictStyleResult']) {
      final at = src.indexOf("name: '$name'");
      expect(at, greaterThan(-1), reason: name);
      final next = src.indexOf('GoRoute(', at);
      expect(src.substring(at, next == -1 ? src.length : next), contains('ClinicalQuizGate('), reason: name);
    }
  });
}
