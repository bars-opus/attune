// Removal semantics for hide and mute (ATTUNE_MASTER_SPEC.md §8.11 "Muting
// and hiding").
//
// Hide and mute are the only feed actions that REMOVE rows rather than flip a
// field on one: there is no `isHidden` on OpinionModel, because a hidden or
// muted opinion simply stops being returned by the feed RPCs. The server is
// the authority on that filtering — these tests cover only the client's
// optimistic half, i.e. that `removeWhere` drops exactly the rows it should
// and leaves the rest of the list intact.
//
// The predicates themselves (`o.id == x`, `o.authorHandle == h`) are asserted
// here rather than trusted, since the mute case is the one place a wrong
// predicate would be quietly destructive: matching on the wrong field could
// empty a feed instead of removing one author.

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/opinions/data/models/opinion_model.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

OpinionModel _opinion(String id, {required String authorHandle}) {
  return OpinionModel(
    id: id,
    authorHandle: authorHandle,
    isMine: false,
    content: 'content-$id',
    relationshipStatus: 'single',
    likeCount: 0,
    dislikeCount: 0,
    commentCount: 0,
    createdAt: DateTime(2026, 7, 25),
  );
}

/// Never actually called: every test seeds notifier state directly and then
/// exercises the pure list transform, so no RPC is issued. It exists only to
/// satisfy the repository provider override that DiscoverFeedNotifier reads
/// during build.
class _UnusedRepository implements OpinionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no RPC should be issued by these tests');
}

/// Seeds a feed notifier with [seed] without letting its real `build()` run —
/// build() would hit Supabase and the cache, neither of which is under test
/// here. Overriding the state after the fact is enough because `removeWhere`
/// reads and writes `state` and nothing else.
ProviderContainer _containerWith(List<OpinionModel> seed) {
  final container = ProviderContainer(
    overrides: [
      opinionRepositoryProvider.overrideWithValue(_UnusedRepository()),
      supabaseClientProvider.overrideWithValue(
        // Never used: currentUserIdProvider is not read on the paths under
        // test, and the repository above throws on any call.
        _NullSupabase(),
      ),
    ],
  );
  addTearDown(container.dispose);
  container.read(discoverFeedProvider.notifier).state = AsyncData(seed);
  return container;
}

class _NullSupabase implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no Supabase call should be issued');
}

void main() {
  group('DiscoverFeedNotifier.removeWhere', () {
    test('hide drops only the targeted opinion', () {
      final container = _containerWith([
        _opinion('a', authorHandle: 'handle-1'),
        _opinion('b', authorHandle: 'handle-2'),
        _opinion('c', authorHandle: 'handle-1'),
      ]);
      final notifier = container.read(discoverFeedProvider.notifier);

      notifier.removeWhere((o) => o.id == 'b');

      // Only 'b' goes; the two sharing an author with each other are
      // untouched, since hide is per-post and carries no author implication.
      expect(
        notifier.state.value!.map((o) => o.id),
        equals(['a', 'c']),
      );
    });

    test('mute drops every opinion by that author, and only that author', () {
      final container = _containerWith([
        _opinion('a', authorHandle: 'handle-1'),
        _opinion('b', authorHandle: 'handle-2'),
        _opinion('c', authorHandle: 'handle-1'),
        _opinion('d', authorHandle: 'handle-3'),
      ]);
      final notifier = container.read(discoverFeedProvider.notifier);

      notifier.removeWhere((o) => o.authorHandle == 'handle-1');

      // Retroactive within the feed (§8.11): BOTH of handle-1's existing
      // posts go, not just the one the mute was triggered from.
      expect(
        notifier.state.value!.map((o) => o.id),
        equals(['b', 'd']),
      );
    });

    test('leaves the list identical when nothing matches', () {
      final seed = [
        _opinion('a', authorHandle: 'handle-1'),
        _opinion('b', authorHandle: 'handle-2'),
      ];
      final container = _containerWith(seed);
      final notifier = container.read(discoverFeedProvider.notifier);
      final before = notifier.state.value;

      notifier.removeWhere((o) => o.id == 'not-in-this-feed');

      // Identity, not just equality: the guard clause must skip the rebuild
      // entirely so patching every feed blindly (as hide/mute both do) cannot
      // churn a feed that never held the row.
      expect(identical(notifier.state.value, before), isTrue);
    });

    test('can empty the list without error', () {
      final container = _containerWith([
        _opinion('a', authorHandle: 'handle-1'),
        _opinion('b', authorHandle: 'handle-1'),
      ]);
      final notifier = container.read(discoverFeedProvider.notifier);

      notifier.removeWhere((o) => o.authorHandle == 'handle-1');

      expect(notifier.state.value, isEmpty);
    });
  });
}
