// Streaks have their own manual page, listed only while streak capture is
// on, and it says what a person needs to trust them: view once, the
// replay setting, the 30-minute window, and a failed send.
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DocumentationRegistry.initialize);

  test('streaks is a topic, gated on streak capture', () {
    expect(DocumentationRegistry.getById('streaks'), isNotNull);
    expect(
      DocumentationRegistry.requiredFlags('streaks'),
      unorderedEquals([
        ChatFeatureFlags.ephemeralVideo,
        ChatFeatureFlags.videoSharing,
      ]),
    );
  });

  testWidgets('it explains view once, replays, the window and a failed send', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final module = DocumentationRegistry.getById('streaks')!;
    final text = [
      for (final s in module.getSections(context))
        for (final c in s.contents) '${c.title} ${c.content}',
      for (final f in module.getFAQs(context)) '${f.question} ${f.answer}',
    ].join('\n');
    expect(text, contains('once'));
    expect(text, contains('Allow streak replays'));
    expect(text, contains('30 minutes'));
    expect(text, contains('Not sent'));
  });
}
