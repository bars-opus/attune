import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/features/together/data/together_ai_repository.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_ai.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/free_window_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_ai_test.dart' show FakeAiGateway;
import 'together_repository_test.dart' show FakeTogetherGateway;

final _w = FreeWindow(
  start: DateTime(2026, 11, 5, 19),
  end: DateTime(2026, 11, 5, 22),
  partnerFrom: '14:00',
  partnerTo: '17:00',
  partnerDiffers: true,
);

Future<(FakeTogetherGateway, FakeAiGateway)> _open(
  WidgetTester t, {
  bool ai = true,
  TogetherAiException? error,
}) async {
  t.view.physicalSize = const Size(1170, 4000);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({
    'propose_couple_event': (_) => 'p1',
    'list_together_items': (_) => const [],
  });
  final a = FakeAiGateway(
    error: error,
    response: {
      'ideas': [
        {
          'title': 'Cook a new recipe',
          'blurb': 'Pick one neither of you has tried.',
        },
        {'title': 'Night walk', 'blurb': 'Thirty minutes, phones away.'},
        {'title': 'Board games', 'blurb': 'Best of three.'},
      ],
    },
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherAiRepositoryProvider.overrideWithValue(TogetherAiRepository(a)),
        togetherAiAvailableProvider.overrideWith((ref, id) async => ai),
        togetherMeProvider.overrideWithValue('ama'),
        togetherPartnerIdProvider.overrideWith((ref) async => 'kofi'),
        togetherDeviceTimezoneProvider.overrideWith((ref) async => 'UTC'),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        timeline.togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder:
                      (c) => TextButton(
                        onPressed:
                            () => showFreeWindowSheet(
                              c,
                              relationshipId: 'r1',
                              window: _w,
                              partnerName: 'Kofi',
                            ),
                        child: const Text('open'),
                      ),
                ),
              ),
            ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return (g, a);
}

void main() {
  testWidgets('three ideas; picking one suggests it for that time', (t) async {
    final (g, a) = await _open(t);
    await t.tap(find.text('Get 3 ideas'));
    await t.pumpAndSettle();
    expect(a.bodies.single['window_start_local'], '2026-11-05T19:00');
    expect(find.text('Night walk'), findsOneWidget);
    await t.tap(find.text('Night walk'));
    await t.pumpAndSettle();
    // The suggestion sheet opens prefilled; saving sends a proposal.
    expect(find.text('Night walk'), findsWidgets);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    final call = g.calls.singleWhere((c) => c.$1 == 'propose_couple_event');
    expect((call.$2['p_event'] as Map)['title'], 'Night walk');
  });

  testWidgets('without AI it still offers to suggest a time', (t) async {
    await _open(t, ai: false);
    expect(find.text('Get 3 ideas'), findsNothing);
    expect(find.text('Suggest something for this time'), findsOneWidget);
  });

  testWidgets('if AI is switched off mid-way, ideas say so plainly', (t) async {
    await _open(t, error: const TogetherAiException('FEATURE_DISABLED'));
    await t.tap(find.text('Get 3 ideas'));
    await t.pumpAndSettle();
    expect(
      find.textContaining("AI help isn't available for you two right now"),
      findsOneWidget,
    );
  });
}
