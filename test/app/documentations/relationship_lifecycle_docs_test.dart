// The manual's "Your stories" item says, in plain words, what sealing your
// side means for downloading them (stories final review M6): a sealed
// chapter drops out of Download my data at once
// (relationship_chat_open_for), so the 30 days no longer apply.
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DocumentationRegistry.initialize);

  testWidgets('Your stories says sealing ends the download at once', (
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
    final module = DocumentationRegistry.getById('relationshipLifecycle')!;
    final item = [
      for (final s in module.getSections(context)) ...s.contents,
    ].singleWhere((c) => c.id == 'lifecycle_end_stories');
    expect(item.content, contains('for both of you'));
    expect(item.content, contains('Download my data'));
    expect(
      item.content,
      contains(
        'Sealing your side ends this at once: your stories leave your '
        'download and can\'t be fetched again, so download first if you '
        'want a copy.',
      ),
    );
  });
}
