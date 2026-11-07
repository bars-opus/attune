// Spec 2 W2 (§2.1, §4.10, R7): Healing never decides when someone can
// date. A finished journey shows no Dating outcome, the repository and the
// model know no Dating status, and the manual says the same.
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';
import 'w9e/support/healing_fakes.dart';

HealingJourney _finished({String status = 'completed'}) =>
    HealingJourney.fromJson({
      'id': 'j9',
      'user_id': 'ama',
      'relationship_id': 'r1',
      'breakup_at': '2026-08-01T00:00:00Z',
      'breakup_at_source': 'relationship',
      'status': status,
      'current_stage': 5,
      'reflection_answers': <String, dynamic>{},
      'reflection_completed_at': '2026-08-02T00:00:00Z',
      'post_mortem_status': 'completed',
      'post_mortem_completed_at': '2026-08-03T00:00:00Z',
      'pattern_awareness_completed_at': '2026-08-04T00:00:00Z',
      'portrait_status': 'completed',
      'portrait_completed_at': '2026-08-05T00:00:00Z',
      'readiness_stage_completed_at': '2026-08-06T00:00:00Z',
      'completed_at': '2026-08-06T00:00:00Z',
      // A column the app no longer reads.
      'eligible_for_dating_opt_in_at': '2026-08-06T00:00:00Z',
      'created_at': '2026-08-02T00:00:00Z',
      'updated_at': '2026-08-06T00:00:00Z',
    });

List<String> _texts(BuildContext context, DocumentationModule m) => [
  m.getTitle(context),
  m.getSubtitle(context),
  for (final s in m.getSections(context)) ...[
    s.title,
    s.subtitle ?? '',
    for (final c in s.contents) ...[c.title, c.content, ...?c.bulletPoints],
  ],
  for (final f in m.getFAQs(context)) ...[f.question, f.answer],
];

void main() {
  testWidgets('a finished journey offers no Dating outcome (even a row '
      'read before the migration rewrote its old status)', (t) async {
    final repo =
        FakeHealingRepository()
          ..latest['ama'] = _finished(status: 'eligible_for_dating_opt_in');
    await pumpFlowScreen(
      t,
      () => const HealingJourneyScreen(),
      size: const Size(900, 1200),
      overrides: [
        healingRepositoryProvider.overrideWithValue(repo),
        healingAccountProvider.overrideWith((ref) => 'ama'),
      ],
    );
    expect(find.textContaining('Dating'), findsNothing);
  });

  test('the repository and the model know no Dating status', () {
    final repo =
        File(
          'lib/features/healing/data/repositories/healing_repository.dart',
        ).readAsStringSync();
    final model =
        File(
          'lib/features/healing/data/models/healing_journey.dart',
        ).readAsStringSync();
    expect(repo, isNot(contains('eligible_for_dating_opt_in')));
    // Fix round 1 (I-2): a finished journey (every migrated one included)
    // stays readable.
    expect(repo, contains("['active', 'paused', 'completed']"));
    expect(model, isNot(contains('isEligibleForDating')));
    expect(model, isNot(contains('eligibleForDatingOptInAt')));
    expect(_finished().isCompleted, isTrue);
  });

  testWidgets('the manual never says Healing gates Dating', (t) async {
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
    final all = [
      for (final m in <DocumentationModule>[
        HealingDocs(),
        AboutAttuneDocs(),
        DatingModeDocs(),
      ])
        ..._texts(context, m),
    ].join('\n');
    for (final stale in [
      'eligible through Healing',
      '8 weeks',
      'potentially eligible',
      'matched on who you actually are',
      'readiness score that needs to reflect',
    ]) {
      expect(all, isNot(contains(stale)), reason: stale);
    }
    expect(all, contains('Healing never decides when you can date'));
    expect(all, contains('based on what you both say you want'));
  });

  // Batch 4 addition: the positive sentence above is also in Dating's topic,
  // so pin that Healing's own topic and FAQ say it too.
  testWidgets('Healing\'s own topic and FAQ say it never decides', (t) async {
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
    final healing = _texts(context, HealingDocs()).join('\n');
    expect(healing, contains('Healing never decides when you can date'));
    expect(
      healing,
      contains('Does finishing the journey decide when I can date?'),
    );
    expect(healing, contains('Healing never decides that'));
  });

  // Fix round 1 (M-1): Dating's own topic says it too, in both places.
  testWidgets('Dating\'s own topic says Healing never decides', (t) async {
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
    final dating = _texts(context, DatingModeDocs()).join('\n');
    expect(dating, contains('Healing never decides when you can date.'));
    expect(dating, contains('Healing never decides it.'));
    expect(dating.toLowerCase(), isNot(contains('finished your healing')));
    expect(dating.toLowerCase(), isNot(contains('after healing')));
  });
}
