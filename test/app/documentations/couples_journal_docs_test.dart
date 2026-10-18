// The Couples journal topic: what Planning's help button opens. It names
// every related topic in its own text with a link, so someone who never
// finds the Related tab still gets there.
import 'package:attune/app/documentations/user_manual/data/couples_journal_docs.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/widgets/documentation_tab_view.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Set<String> flags) => ProviderScope(
  overrides: [documentationFlagsProvider.overrideWith((ref) async => flags)],
  child: ScreenUtilInit(
    designSize: const Size(375, 812),
    builder:
        (_, __) => MaterialApp(
          home: Scaffold(
            body: DocumentationTabView(module: CouplesJournalDocs()),
          ),
        ),
  ),
);

// The back row's label is "Back to <topic>", merged with the title it shows.
Finder _back(String title) => find.bySemanticsLabel(RegExp('^Back to $title'));

Finder _link(String title) => find.widgetWithText(InfoRowWidget, title);

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).last);
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

void main() {
  setUp(DocumentationRegistry.initialize);

  test(
    'Planning, the calendar, the map, the reflection journal and endings are related',
    () {
      expect(DocumentationRegistry.getRelatedModuleIds('couplesJournal'), [
        'planning',
        'together',
        'coupleMap',
        'reflectionJournal',
        'relationshipLifecycle',
      ]);
    },
  );

  testWidgets('its own text links every related topic', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final linked = [
      for (final s in CouplesJournalDocs().getSections(context))
        for (final c in s.contents)
          if (c.type == ManualContentType.link) c.linkedModuleId,
    ];
    expect(
      linked.toSet(),
      DocumentationRegistry.getRelatedModuleIds('couplesJournal').toSet(),
    );
  });

  testWidgets('a link opens its topic in place; back retraces every step', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(_app({ChatFeatureFlags.coupleMap}));
    await t.pumpAndSettle();
    await _scrollTo(t, _link('Planning'));
    await t.tap(_link('Planning'));
    await t.pumpAndSettle();
    expect(_back('Couples journal'), findsOneWidget);

    // Two deep: Planning's own Related tab, then the calendar.
    await t.tap(find.text('Related'));
    await t.pumpAndSettle();
    await t.tap(find.text('Together calendar').first);
    await t.pumpAndSettle();
    expect(_back('Planning'), findsOneWidget);

    await t.tap(_back('Planning'));
    await t.pumpAndSettle();
    expect(_back('Couples journal'), findsOneWidget);
    await t.tap(_back('Couples journal'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Back to')), findsNothing);
    semantics.dispose();
  });

  testWidgets('a link to a switched-off feature is left out', (t) async {
    await t.pumpWidget(_app(const {}));
    await t.pumpAndSettle();
    await _scrollTo(t, _link('Pausing, ending and your space'));
    expect(_link('Your map'), findsNothing);
  });
}
