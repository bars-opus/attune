// Spec 1 W5 (§5.2 user manual): the About us topic is listed only while
// flow_signin_v2, flow_paths_v2, flow_couples_v2 and couple_profile are on.
import 'package:attune/app/documentations/user_manual/data/about_us_docs.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the About us topic needs all four flags', () {
    DocumentationRegistry.initialize();
    bool listed(Set<String> on) =>
        DocumentationRegistry.visibleModules(on).any((m) => m.id == 'aboutUs');
    const all = {
      'flow_signin_v2',
      'flow_paths_v2',
      'flow_couples_v2',
      'couple_profile',
    };
    expect(DocumentationRegistry.getById('aboutUs'), isNotNull);
    expect(listed(all), isTrue);
    for (final missing in all) {
      expect(listed({...all}..remove(missing)), isFalse, reason: missing);
    }
  });

  // Fix round 1 (review I-2; §2.1, the couple-name rule): the partner is
  // named or "your partner", never "they"; the pair is never "both" or
  // "the two of you".
  testWidgets('the About us manual never says they, both or the two of you', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    final docs = AboutUsDocs();
    final strings = <String>[
      docs.getTitle(context),
      docs.getSubtitle(context),
      for (final section in docs.getSections(context)) ...[
        section.title,
        if (section.subtitle != null) section.subtitle!,
        for (final content in section.contents) ...[
          content.title,
          content.content,
          ...?content.bulletPoints,
        ],
      ],
      for (final faq in docs.getFAQs(context)) ...[faq.question, faq.answer],
    ];
    expect(strings.length, greaterThan(10));
    final banned = RegExp(
      r"\bthey\b|\bthem\b|\btheir\b|\bboth\b|\bthe two of you\b",
      caseSensitive: false,
    );
    for (final text in strings) {
      expect(text, isNot(matches(banned)), reason: text);
    }
  });
}
