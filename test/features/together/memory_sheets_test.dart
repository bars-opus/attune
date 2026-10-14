import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_story.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:attune/features/together/presentation/widgets/memory_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('the prompt question names the day plainly', () {
    MemoryPrompt on(DateTime d) =>
        MemoryPrompt(eventId: 'e', title: 'Dinner', day: d);
    final now = DateTime(2026, 11, 9, 10); // a Monday
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 9)), now),
      'Add a line about today?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 8)), now),
      'Add a line about yesterday?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 11, 7)), now),
      'Add a line about Saturday?',
    );
    expect(
      memoryPromptQuestion(on(DateTime(2026, 10, 20)), now),
      'Add a line about Oct 20?',
    );
  });

  test('a repeating event offers no memory (it has no single day)', () {
    TogetherItem walk({String? rrule}) => TogetherItem.fromRow({
      'item_kind': 'event',
      'item_id': 'e1',
      'item_date': '2026-10-06',
      'starts_at': '2026-10-06T07:00:00+00:00',
      'ends_at': '2026-10-06T08:00:00+00:00',
      'all_day': false,
      'tz': 'Africa/Accra',
      'title': 'Walk',
      'participant_ids': ['ama', 'kofi'],
      'owner_id': null,
      'created_by': 'ama',
      'visibility': 'shared',
      'status': 'confirmed',
      'source_ref': {'kind': 'event', if (rrule != null) 'rrule': rrule},
    });
    final now = DateTime(2026, 10, 7);
    expect(canAddMemory(walk(), now, 'ama'), isTrue);
    expect(canAddMemory(walk(rrule: 'FREQ=WEEKLY'), now, 'ama'), isFalse);
  });

  testWidgets('a line becomes a memory; a blank one is not sent', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final g = FakeTogetherGateway({'add_event_memory': (_) => 'm1'});
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
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
                              () => showAddMemorySheet(
                                c,
                                eventId: 'e1',
                                title: 'Dinner at Buka',
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
    expect(find.text('Dinner at Buka'), findsOneWidget);
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls, isEmpty);
    await t.enterText(find.byType(TextField).first, 'The jollof was perfect');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(g.calls.single.$2, {
      'p_event_id': 'e1',
      'p_line': 'The jollof was perfect',
    });
    expect(find.text('Added to your story.'), findsOneWidget);
  });
}
