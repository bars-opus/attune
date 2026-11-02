// Spec 1 W3c (B7 ruling M-3): the journal topic is listed for everyone, so
// its reminder sentences only appear while the reminder exists
// (flow_signin_v2 and flow_paths_v2); with them off it reads as before.
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _journalText(WidgetTester tester, Set<String> flags) async {
  late BuildContext context;
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        documentationFlagsProvider.overrideWith((ref) async => flags),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (c, ref, _) {
            ref.watch(documentationFlagsProvider);
            context = c;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final module = DocumentationRegistry.getById('reflectionJournal')!;
  return [
    for (final s in module.getSections(context))
      for (final c in s.contents) '${c.title} ${c.content}',
    for (final f in module.getFAQs(context)) '${f.question} ${f.answer}',
  ].join('\n');
}

void main() {
  setUp(DocumentationRegistry.initialize);

  test('the reminder passage needs flow_signin_v2 and flow_paths_v2', () {
    expect(
      DocumentationRegistry.passageVisible('journalReminder', const {}),
      isFalse,
    );
    expect(
      DocumentationRegistry.passageVisible('journalReminder', const {
        'flow_paths_v2',
      }),
      isFalse,
    );
    expect(
      DocumentationRegistry.passageVisible('journalReminder', const {
        'flow_signin_v2',
        'flow_paths_v2',
      }),
      isTrue,
    );
    expect(
      DocumentationRegistry.allRequiredFlags,
      containsAll(['flow_signin_v2', 'flow_paths_v2']),
    );
  });

  testWidgets('flags off: no reminder, no Your space', (tester) async {
    final text = await _journalText(tester, const {});
    expect(text, isNot(contains('Your space')));
    expect(text, isNot(contains('unless you set one')));
    expect(text, contains('no reminders nagging you to write'));
  });

  testWidgets('flags on: a reminder only if you set one', (tester) async {
    final text = await _journalText(tester, const {
      'flow_signin_v2',
      'flow_paths_v2',
    });
    expect(text, contains('No reminders unless you set one.'));
    expect(text, contains('Remind me to write'));
    expect(text, isNot(contains('nagging')));
  });
}
