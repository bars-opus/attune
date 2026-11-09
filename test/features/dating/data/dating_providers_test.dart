import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../support/dating_fakes.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

void main() {
  test('M-1: datingAccountProvider follows the signed-in user: one '
      'account, the next, then signed out', () {
    final user = StateProvider<User?>((ref) => _user('ama'));
    final c = ProviderContainer(
      overrides: [currentUserProvider.overrideWith((ref) => ref.watch(user))],
    );
    addTearDown(c.dispose);
    final seen = <String?>[];
    c.listen<String?>(
      datingAccountProvider,
      (_, next) => seen.add(next),
      fireImmediately: true,
    );
    c.read(user.notifier).state = _user('kofi');
    expect(c.read(datingAccountProvider), 'kofi');
    c.read(user.notifier).state = null;
    expect(c.read(datingAccountProvider), isNull);
    expect(seen, ['ama', 'kofi', null]);
  });

  test('M-2, D8: a failed read for the next account shows nothing of the '
      'last account', () async {
    final gateway = FakeDatingHomeGateway(
      home: const DatingHome(state: DatingHomeState.active),
    );
    final c = ProviderContainer(
      overrides: [datingHomeGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(c.dispose);
    final first = c.listen(datingHomeProvider('ama'), (_, __) {});
    expect(
      (await c.read(datingHomeProvider('ama').future)).state,
      DatingHomeState.active,
    );
    gateway.readError = StateError('offline');
    final next = c.listen(datingHomeProvider('kofi'), (_, __) {});
    first.close();
    await expectLater(
      c.read(datingHomeProvider('kofi').future),
      throwsA(isA<StateError>()),
    );
    final kofi = c.read(datingHomeProvider('kofi'));
    expect(kofi.hasError, isTrue);
    expect(kofi.hasValue, isFalse);
    expect(kofi.valueOrNull?.state, isNot(DatingHomeState.active));
    await Future<void>.delayed(Duration.zero);
    expect(c.exists(datingHomeProvider('ama')), isFalse);
    next.close();
  });

  test('signed out: unavailable, and the server is never asked', () async {
    final gateway = FakeDatingHomeGateway();
    final c = ProviderContainer(
      overrides: [
        datingHomeGatewayProvider.overrideWithValue(gateway),
        datingAccountProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    final home = await c.read(datingHomeProvider(null).future);
    expect(home.state, DatingHomeState.unavailable);
    expect(gateway.reads, 0);
  });

  test('D8: the next account starts empty while its read is held, and the '
      'last account\'s entry is disposed', () async {
    final gateway = FakeDatingHomeGateway(
      home: const DatingHome(state: DatingHomeState.active),
    );
    final account = StateProvider<String?>((ref) => 'ama');
    final c = ProviderContainer(
      overrides: [
        datingHomeGatewayProvider.overrideWithValue(gateway),
        datingAccountProvider.overrideWith((ref) => ref.watch(account)),
      ],
    );
    addTearDown(c.dispose);
    final first = c.listen(datingHomeProvider('ama'), (_, __) {});
    expect(
      (await c.read(datingHomeProvider('ama').future)).state,
      DatingHomeState.active,
    );
    gateway.hold = Completer<DatingHome>();
    c.read(account.notifier).state = 'kofi';
    final next = c.listen(datingHomeProvider('kofi'), (_, __) {});
    first.close();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(datingHomeProvider('kofi')).hasValue, isFalse);
    expect(c.exists(datingHomeProvider('ama')), isFalse);
    gateway.hold!.complete(const DatingHome(state: DatingHomeState.notStarted));
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(datingHomeProvider('kofi')).value?.state,
      DatingHomeState.notStarted,
    );
    next.close();
  });
}
