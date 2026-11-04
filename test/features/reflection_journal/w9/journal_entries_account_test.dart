// Spec 1 W9c fix round 1 (D8, shared phones): the Conversations row's list
// (journalEntriesProvider) is the signed-in account's. A background refresh
// started for the last account, behind its cached list, never lands after
// another account signs in. Its own file: the cache is served once per
// process (JournalEntriesNotifier._servedCache is static). Fix round 2
// (re-review N-1): J1 never counts the last account's notes while the next
// account's first read is out, or after it fails.
import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show userQuizzesStatusProvider;
import 'package:attune/features/reflection_journal/data/cache/reflection_journal_cache.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../support/fake_journal.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-04T00:00:00Z',
);

JournalEntry _entry(String id, String who, String title) => JournalEntry(
  id: id,
  userId: who,
  content: 'x',
  createdAt: DateTime(2026, 11, 4),
  updatedAt: DateTime(2026, 11, 4),
  title: title,
);

/// Each read answers for the account signed in when it was sent; the
/// first read (Ama's, behind her cached list) waits for [firstGate].
class _PerAccount extends FakeJournalRepository {
  String account = 'ama';
  final firstGate = Completer<void>();
  var _reads = 0;

  @override
  Future<List<JournalEntry>> getEntries() async {
    final who = account;
    if (_reads++ == 0) await firstGate.future;
    return [
      who == 'ama'
          ? _entry('a1', 'ama', 'Ama entry')
          : _entry('k1', 'kofi', 'Kofi entry'),
    ];
  }
}

/// Kofi's reads wait for [kofiHold], then fail when [kofiFails].
class _KofiHeld extends FakeJournalRepository {
  String account = 'ama';
  final kofiHold = Completer<void>();
  bool kofiFails = false;

  @override
  Future<List<JournalEntry>> getEntries() async {
    final who = account;
    if (who == 'kofi') {
      await kofiHold.future;
      if (kofiFails) throw Exception('offline');
      return [_entry('k1', 'kofi', 'Kofi entry')];
    }
    return [_entry('a1', 'ama', 'Ama entry')];
  }
}

void main() {
  test(
    'a refresh for the last account never lands after another signs in',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await ReflectionJournalCache(
        prefs,
      ).writeEntries('ama', [_entry('a1', 'ama', 'Ama entry')]);
      final repo = _PerAccount();
      final signedIn = StateProvider<User?>((ref) => _user('ama'));
      final c = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(signedIn)),
          reflectionJournalRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c.dispose);
      c.listen(journalEntriesProvider, (_, __) {});
      final cached = await c.read(journalEntriesProvider.future);
      expect(cached.single.title, 'Ama entry'); // the cache, refresh pending

      repo.account = 'kofi';
      c.read(signedIn.notifier).state = _user('kofi');
      final kofi = await c.read(journalEntriesProvider.future);
      expect(kofi.single.title, 'Kofi entry');

      repo.firstGate.complete(); // Ama's refresh answers late
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(journalEntriesProvider).value!.single.title, 'Kofi entry');
    },
  );

  // After the refresh test: the cache is served once per process.
  test('J1 never counts the last account\'s notes for the next one', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = _KofiHeld();
    final signedIn = StateProvider<User?>((ref) => _user('ama'));
    final c = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(signedIn)),
        reflectionJournalRepositoryProvider.overrideWithValue(repo),
        sharedPreferencesProvider.overrideWithValue(prefs),
        userQuizzesStatusProvider.overrideWith((ref) async => {}),
      ],
    );
    addTearDown(c.dispose);
    c.listen(firstActionInputsProvider, (_, __) {});
    await c.read(journalEntriesProvider.future);
    expect(c.read(firstActionInputsProvider).hasNote, isTrue);
    expect(c.read(journalOwnEntriesProvider)!.single.title, 'Ama entry');

    repo.account = 'kofi';
    c.read(signedIn.notifier).state = _user('kofi');
    await Future<void>.delayed(Duration.zero);
    // Kofi's read is out: Ama's list is still the carried value.
    expect(c.read(journalEntriesProvider).valueOrNull, isNotNull);
    expect(c.read(journalOwnEntriesProvider), isNull);
    expect(c.read(firstActionInputsProvider).hasNote, isNull);

    repo.kofiFails = true;
    repo.kofiHold.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(journalEntriesProvider).hasError, isTrue);
    expect(c.read(journalOwnEntriesProvider), isNull);
    expect(c.read(firstActionInputsProvider).hasNote, isNull);
  });
}
