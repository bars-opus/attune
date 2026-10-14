import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _row(String id, String date, String kind) => {
  'item_kind': kind,
  'item_id': id,
  'item_date': date,
  'starts_at': null,
  'ends_at': null,
  'all_day': true,
  'tz': null,
  'title': id,
  'participant_ids': ['ama'],
  'owner_id': null,
  'created_by': 'ama',
  'visibility': 'shared',
  'status': 'confirmed',
  'source_ref': {},
};

void main() {
  test('the agenda reads both ranges and groups them', () async {
    final g = FakeTogetherGateway({
      'list_together_items':
          (p) =>
              p['p_start'] == '2026-11-02'
                  ? [_row('rent', '2026-11-02', 'event')]
                  : [_row('beach', '2026-10-20', 'moment')],
    });
    final c = ProviderContainer(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherClockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9)),
        togetherMeProvider.overrideWithValue('ama'),
        togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
    );
    addTearDown(c.dispose);
    final agenda = await c.read(togetherAgendaProvider('r1').future);
    expect(agenda.today.single.id, 'rent');
    expect(agenda.recentMoments.single.id, 'beach');
    expect(g.calls.map((c) => c.$2['p_start']).toSet(), {
      '2026-11-02',
      '2026-08-01',
    });
  });
}
