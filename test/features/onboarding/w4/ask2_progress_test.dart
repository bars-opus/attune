// Spec 1 W4b (§3.8 R5, §5.8): Ask 2 saves as it goes; reopening resumes at
// the first unanswered item; the progress is wiped at sign-out and on
// quick exit, and never names Dating.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/onboarding/data/ask2_progress_store.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/home_harness.dart';

const _uid = 'u-ask2';
const _rel = 'r-ask2';
final _key = Ask2ProgressStore.keyFor(_uid, _rel);

Future<SharedPreferences> _pump(
  WidgetTester tester, [
  Map<String, Object> values = const {},
  List<Override> overrides = const [],
]) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser(_uid))),
        ...overrides,
      ],
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => const Ask2Flow(relationshipId: _rel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  test('the store: shaped to the quiz, empty reads as none', () async {
    SharedPreferences.setMockInitialValues({
      _key: '{"answers":[2,null,"x"],"anchors":["a"]}',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = Ask2ProgressStore(prefs, userId: _uid, relationshipId: _rel);
    final read = store.read(questionCount: 4, anchorCount: 3)!;
    expect(read.answers, [2, null, null, null]);
    expect(read.anchors, ['a', '', '']);
    expect(read.firstUnanswered, 1);
    await store.write(const Ask2Progress(answers: [null], anchors: ['']));
    expect(store.read(questionCount: 1, anchorCount: 1), isNull);
    expect(_key.toLowerCase(), isNot(contains('dating')));
  });

  testWidgets('an answer is saved as it is given', (tester) async {
    final prefs = await _pump(tester);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<int>),
        matching: find.text('3'),
      ),
    );
    await tester.pumpAndSettle();
    final saved = Ask2ProgressStore(
      prefs,
      userId: _uid,
      relationshipId: _rel,
    ).read(questionCount: attachmentQuestions.length, anchorCount: 3);
    expect(saved, isNotNull);
    expect(saved!.answers.first, 3);
  });

  testWidgets('reopening resumes at the first unanswered question', (
    tester,
  ) async {
    final answers = List<int?>.filled(attachmentQuestions.length, null);
    answers[0] = 1;
    answers[1] = 2;
    await _pump(tester, {
      _key:
          '{"answers":${answers.map((a) => a ?? 'null').toList()},"anchors":["","",""]}',
    });
    expect(find.text('A closer look'), findsNothing);
    expect(find.text('Relationship reflection quiz'), findsOneWidget);
    expect(find.textContaining('3 of'), findsWidgets);
  });

  // Review M-3 (§3.8 R5, P-18): finishing clears the saved answers; a
  // failed server write keeps every one of them.
  final everyAnswer = {
    _key:
        '{"answers":${List.filled(attachmentQuestions.length, 1)},'
        '"anchors":["a","b","c"]}',
  };

  testWidgets('finishing clears the saved progress', (tester) async {
    final finished = <String>[];
    final prefs = await _pump(tester, everyAnswer, [
      ask2FinishProvider.overrideWithValue((relationshipId, _, __) async {
        finished.add(relationshipId);
      }),
    ]);
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(finished, [_rel]);
    expect(prefs.containsKey(_key), isFalse);
  });

  testWidgets('a failed finish keeps every answer', (tester) async {
    var attempts = 0;
    final prefs = await _pump(tester, everyAnswer, [
      ask2FinishProvider.overrideWithValue((_, __, ___) async {
        attempts++;
        throw Exception('offline');
      }),
    ]);
    await tester.ensureVisible(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    final kept = Ask2ProgressStore(
      prefs,
      userId: _uid,
      relationshipId: _rel,
    ).read(questionCount: attachmentQuestions.length, anchorCount: 3);
    expect(kept, isNotNull);
    expect(kept!.answers, everyElement(1));
    expect(kept.anchors, ['a', 'b', 'c']);
  });

  test('wiped at sign-out and on quick exit, for every account', () async {
    SharedPreferences.setMockInitialValues({
      _key: '{}',
      Ask2ProgressStore.keyFor('u2', 'r9'): '{}',
      'attune.flow.$_uid.first_action': 'kept-by-this-entry',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.ask2_progress',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.protective, isFalse);
    await entry.run();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where(Ask2ProgressStore.isProgressKey), isEmpty);
    expect(prefs.containsKey('attune.flow.$_uid.first_action'), isTrue);
  });
}
