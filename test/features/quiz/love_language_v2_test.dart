// Spec 5 (R5-5, A2): "What feels loving to me right now" replaces the love
// language typology. Five ratings, optional moments, changeable any time; no
// primary, no "your love language is"; old (v1) results still render.
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_quiz_screen.dart';
import 'package:attune/features/quiz/presentation/screens/love_language_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget home) => ProviderScope(
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (_, __) => MaterialApp(home: home),
  ),
);

final _v2 = LoveLanguageResult(
  ratings: const {
    LovingWay.words: LovingRating.aLot,
    LovingWay.time: LovingRating.aLittle,
    LovingWay.help: LovingRating.aLot,
    LovingWay.touch: LovingRating.notReally,
    LovingWay.gifts: LovingRating.notReally,
  },
  moments: const {LovingMoment.stressed},
  updatedAt: DateTime.utc(2026, 10, 18),
);

void main() {
  group('model', () {
    test('v2 round-trips with its instrument version and no primary', () {
      final json = _v2.toJson();
      expect(json['instrument_version'], 2);
      expect(json.containsKey('primary'), isFalse);
      expect(json.containsKey('secondary'), isFalse);
      expect(LoveLanguageResult.fromJson(json), _v2);
    });

    test('a v1 result is read through the adapter, typology dropped', () {
      final r = LoveLanguageResult.fromJson({
        'words': 40, 'quality_time': 25, 'gifts': 5, 'acts': 15, 'touch': 15,
        'primary': 'words', 'secondary': 'quality_time',
        'completed_at': '2026-07-01T10:00:00Z',
      });
      expect(r.fromEarlierVersion, isTrue);
      expect(r.ratings[LovingWay.words], LovingRating.aLot);
      expect(r.ratings[LovingWay.time], LovingRating.aLot);
      expect(r.ratings[LovingWay.help], LovingRating.aLittle);
      expect(r.ratings[LovingWay.touch], LovingRating.aLittle);
      expect(r.ratings[LovingWay.gifts], LovingRating.notReally);
      expect(r.moments, isEmpty);
    });

    test('the summary names what helps a lot, never a type', () {
      expect(_v2.summary, 'A lot: words, help');
      final none = LoveLanguageResult(ratings: const {}, moments: const {}, updatedAt: DateTime.utc(2026));
      expect(none.summary, 'Not set yet');
    });
  });

  testWidgets('the result says what it is, keeps no typology, and can be changed', (t) async {
    await t.pumpWidget(_app(LoveLanguageResultScreen(result: _v2)));
    await t.pump();
    expect(find.text('What feels loving to me right now'), findsOneWidget);
    expect(find.text('Based on a popular framework, not a science.'), findsOneWidget);
    expect(find.text('When stressed'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.textContaining('love language is'), findsNothing);
    expect(find.textContaining('Primary'), findsNothing);
    expect(find.textContaining('Secondary'), findsNothing);
  });

  testWidgets('the editor rates each way, picks moments, and saves', (t) async {
    t.view.physicalSize = const Size(1170, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    LoveLanguageResult? saved;
    await t.pumpWidget(_app(LoveLanguageQuizScreen(
      save: (r) async => saved = r,
      onSaved: (_) {},
    )));
    await t.pumpAndSettle();
    expect(find.text('Based on a popular framework, not a science.'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('loving-words-aLot')));
    await t.tap(find.byKey(const ValueKey('loving-gifts-aLittle')));
    await t.tap(find.text('When celebrating'));
    await t.tap(find.text('Everyday'));
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pump();
    expect(saved!.ratings[LovingWay.words], LovingRating.aLot);
    expect(saved!.ratings[LovingWay.gifts], LovingRating.aLittle);
    expect(saved!.moments, {LovingMoment.celebrating, LovingMoment.everyday});
  });

  testWidgets('the editor starts from the current answers', (t) async {
    t.view.physicalSize = const Size(1170, 4000);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    LoveLanguageResult? saved;
    await t.pumpWidget(_app(LoveLanguageQuizScreen(
      initial: _v2,
      save: (r) async => saved = r,
      onSaved: (_) {},
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pump();
    expect(saved!.ratings, _v2.ratings);
    expect(saved!.moments, _v2.moments);
  });

  testWidgets('Close goes back one step, not to the root (final review M-3)', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(navigatorKey: nav, home: const Text('Home')),
      ),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Profile'))));
    await t.pumpAndSettle();
    nav.currentState!.push(MaterialPageRoute(builder: (_) => LoveLanguageResultScreen(result: _v2)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
  });
}
