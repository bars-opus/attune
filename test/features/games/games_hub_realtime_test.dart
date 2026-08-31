import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the hub subscribes to game_sessions changes', () {
    // activeGamesProvider was a plain FutureProvider read once in
    // initState, with no realtime and no invalidation. So an invite
    // arriving while the partner was LOOKING at the hub never appeared,
    // and neither did the other side accepting — they had to navigate away
    // and back.
    final providers =
        File(
          'lib/features/games/presentation/providers/games_hub_providers.dart',
        ).readAsStringSync();

    expect(
      providers,
      contains('gameSessionEventsProvider'),
      reason: 'the hub needs a live signal, not a one-shot read',
    );
    expect(
      providers,
      contains('PostgresChangeEvent.all'),
      reason:
          'an INSERT is a new invite and an UPDATE is the partner accepting '
          'or finishing — the hub shows both',
    );
  });

  test('the hub invalidates its lists when a session changes', () {
    final providers =
        File(
          'lib/features/games/presentation/providers/games_hub_providers.dart',
        ).readAsStringSync();

    expect(
      providers,
      contains('invalidate(activeGamesProvider)'),
      reason: 'a live signal that refreshes nothing changes nothing',
    );
    expect(providers, contains('invalidate(recentGamesProvider)'));
  });

  test('the channel is removed when the listener goes', () {
    // A Supabase channel outliving its provider leaks a socket
    // subscription for the rest of the session.
    final providers =
        File(
          'lib/features/games/presentation/providers/games_hub_providers.dart',
        ).readAsStringSync();

    final block = providers.substring(
      providers.indexOf('gameSessionEventsProvider'),
    );
    expect(block, contains('onDispose'));
    expect(block, contains('removeChannel'));
  });

  test('the hub screen watches the events provider', () {
    // The StreamProvider is only created when something listens. A
    // subscription nothing watches is a subscription that never opens, so
    // every other assertion here would hold while the hub stayed stale.
    final screen =
        File(
          'lib/features/games/presentation/screens/games_hub_screen.dart',
        ).readAsStringSync();

    expect(
      screen,
      contains('ref.watch(gameSessionEventsProvider)'),
      reason: 'read() would not keep the subscription alive',
    );
  });
}
