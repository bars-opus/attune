import 'dart:async';

import 'package:attune/features/planning/presentation/planning_providers.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('a Together or Planning signal refetches the range', () async {
    var fetches = 0;
    final g = FakeTogetherGateway({
      'list_together_items': (_) {
        fetches++;
        return const [];
      },
    });
    final together = StreamController<void>.broadcast();
    final planning = StreamController<void>.broadcast();
    addTearDown(together.close);
    addTearDown(planning.close);
    final c = ProviderContainer(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherChangeSignalProvider.overrideWith((ref, id) => together.stream),
        planningChangeSignalProvider.overrideWith((ref, id) => planning.stream),
      ],
    );
    addTearDown(c.dispose);
    final args = (
      relationshipId: 'rel-1',
      start: DateTime(2026, 11, 1),
      end: DateTime(2026, 11, 30),
    );
    c.listen(togetherRangeProvider(args), (_, __) {});
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 1);

    together.add(null);
    await Future<void>.delayed(Duration.zero);
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 2);

    planning.add(null);
    await Future<void>.delayed(Duration.zero);
    await c.read(togetherRangeProvider(args).future);
    expect(fetches, 3);
  });
}
