// Spec 1 W9c, the coordinator's rulings and carries on the writer's card:
// - hide (B7 R-1): once the crisis check answers support_offered for an
//   entry, no reflection for it shows this run: not from the provider's
//   state, not on screen, not after "Not now", not when the answer lands
//   while the entry is open again;
// - PF-C7: every answer either offers the card (support_offered) or puts
//   it away (anything else); only a fresh reflection (completed) is shown
//   again;
// - PF-C6: "Not now" on Patterns keeps it away for the run (never stored);
//   a new support_offered brings it back;
// - fix round 1 (batch-8 review): the support state and the journal's list
//   are the signed-in account's only, and go on sign-out and quick exit
//   (I-1, D8); Patterns' summary gives way to the card after a crisis
//   answer without a manual re-read (I-2); the list card shows for an entry
//   on any page (I-3); "Need support now?" and the manual passage need no
//   flag (I-4); an older request's answer never undoes a newer match (M-3);
// - light and dark contrast, and large text let through.
import 'dart:async';

import 'package:attune/app/device_wipes.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/chat/presentation/widgets/conversations_home_cards.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/planning/presentation/widgets/note_text_block.dart';
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:attune/features/reflection_journal/data/models/journal_entry.dart';
import 'package:attune/features/reflection_journal/data/models/journal_note.dart';
import 'package:attune/features/reflection_journal/presentation/providers/reflection_journal_providers.dart';
import 'package:attune/features/reflection_journal/presentation/screens/journal_entry_screen.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import '../../../helpers/flow_harness.dart';
import '../support/fake_journal.dart';
import '../support/journal_test_app.dart';

const _card =
    "If things feel heavy right now, you don't have to carry it alone. Support is here if you want it.";
const _old = 'An older reflection.';
const _away = 'Patterns will show here again later';

const _offered = {'status': 'support_offered'};

/// The server answers each analysis in turn from [answers]; [gate], when
/// set, holds every answer back (a slow network), [gates] one call's.
/// [crisisMovesPatterns]: a support_offered answer also makes Patterns
/// answer support_offered (the entry is now the newest, and matches).
class _Answers extends FakeJournalRepository {
  _Answers(this.answers) : super(now: DateTime.now());

  final List<Map<String, dynamic>> answers;
  String patterns = 'support_offered';
  int patternsReads = 0;
  Completer<void>? gate;
  final gates = <int, Completer<void>>{};
  bool crisisMovesPatterns = false;
  var _calls = 0;

  @override
  Future<JournalAnalysis> analyseEntry(String entryId) async {
    analysed.add(entryId);
    final n = _calls++;
    await gate?.future;
    await gates[n]?.future;
    final answer = JournalAnalysis.fromJson(answers[n]);
    if (crisisMovesPatterns && answer.isSupportOffered) {
      patterns = 'support_offered';
    }
    return answer;
  }

  @override
  Future<({String status, String? summary, int entryCount})>
  getPatterns() async {
    patternsReads++;
    return (
      status: patterns,
      summary: patterns == 'completed' ? 'A summary of your entries.' : null,
      entryCount: 1,
    );
  }
}

JournalAnalysis _reflection(String observation) => JournalAnalysis.fromJson({
  'status': 'completed',
  'tone': 'heavy',
  'observation': observation,
  'confidence': 'low',
});

Future<void> _type(WidgetTester t, String text) async {
  t
      .state<NoteTextBlockState>(find.byType(NoteTextBlock).first)
      .controller
      .replaceText(0, 0, text, TextSelection.collapsed(offset: text.length));
  await t.pump();
}

Future<void> _back(WidgetTester t) async {
  t.state<NavigatorState>(find.byType(Navigator).first).pop();
  await t.pumpAndSettle();
}

/// Opens [title], writes, and leaves (the analysis runs as it closes).
Future<void> _write(WidgetTester t, String title, String text) async {
  await t.tap(find.text(title));
  await t.pumpAndSettle();
  await _type(t, text);
  await _back(t);
  await t.pumpAndSettle();
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-11-04T00:00:00Z',
);

/// Who is signed in, for the shared-phone tests.
final _signedIn = StateProvider<User?>((ref) => _user('ama'));

/// Whether the Conversations card is on screen (sign-out leaves home).
final _rowShown = StateProvider<bool>((ref) => true);

/// Two accounts' journals on one phone: each sees only its own entries.
class _TwoAccounts extends _Answers {
  _TwoAccounts(super.answers);

  final owner = <String, String>{};
  String? account = 'ama';

  /// Reads sent while [held] is signed in wait for [hold]; with [failHeld]
  /// they then fail (a network error).
  String? held;
  Completer<void>? hold;
  bool failHeld = false;
  int listCalls = 0;
  final sweptFor = <String?>[];

  JournalEntry addFor(String who, String title, {DateTime? createdAt}) {
    final e = addEntry(title: title, text: '', createdAt: createdAt);
    owner[e.id] = who;
    // As the server sends it: the owner's id on every row.
    return entries[e.id] = JournalEntry(
      id: e.id,
      userId: who,
      content: e.content,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      title: e.title,
    );
  }

  Future<void> _wait(String? who) async {
    if (who == null || who != held) return;
    await hold?.future;
    if (failHeld) throw Exception('offline');
  }

  @override
  Future<JournalListPage> listEntries({
    DateTime? before,
    int limit = 30,
  }) async {
    listCalls++;
    final who = account; // answers for whoever sent it
    await _wait(who);
    final page = await super.listEntries(before: before, limit: 1000);
    bool mine(JournalEntrySummary e) => owner[e.id] == who;
    final pinned = page.pinned.where(mine).toList();
    final rows = page.entries.where(mine).toList();
    return JournalListPage(
      pinned: before != null ? const [] : pinned,
      entries: rows.take(limit).toList(),
      hasMore: rows.length > limit,
    );
  }

  @override
  Future<List<JournalEntry>> getEntries() async {
    final who = account;
    await _wait(who);
    return [
      for (final e in await super.getEntries())
        if (owner[e.id] == who) e,
    ];
  }

  @override
  Future<int> purgeMyDeleted() async {
    sweptFor.add(account);
    return super.purgeMyDeleted();
  }

  /// Ama's newest entry matches; Kofi's journal has a summary.
  @override
  Future<({String status, String? summary, int entryCount})> getPatterns() {
    patterns = account == 'ama' ? 'support_offered' : 'completed';
    return super.getPatterns();
  }
}

Future<void> _switchTo(WidgetTester t, _TwoAccounts repo, String? who) async {
  _container(t).read(_signedIn.notifier).state =
      who == null ? null : _user(who);
  repo.account = who;
  await t.pumpAndSettle();
}

/// Switches without settling: the frames while the new account's first
/// read is still out (batch-8 re-review N-1).
Future<void> _switchHeld(
  WidgetTester t,
  ProviderContainer c,
  _TwoAccounts repo,
  String who,
) async {
  repo
    ..held = who
    ..hold = Completer<void>();
  repo.account = who;
  c.read(_signedIn.notifier).state = _user(who);
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets(
    'support_offered: the reflection stays hidden, in state and on screen, '
    'after "Not now" too',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _Answers([_offered])..analysisFor = _reflection(_old);
      final e = repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      expect(find.text(_card), findsOneWidget);

      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget);
      expect(find.text(_old), findsNothing);
      expect(
        _container(t).read(journalEntryDetailProvider(e.id)).value!.analysis,
        isNull,
      );

      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      expect(find.text(_old), findsNothing); // put away, still no reflection
      await t.tap(find.byTooltip('Entry options'));
      await t.pumpAndSettle();
      await t.tap(find.text('Pin')); // the entry is read again
      await t.pumpAndSettle();
      expect(repo.entries[e.id]!.pinnedAt, isNotNull);
      expect(find.text(_old), findsNothing);
      await _back(t);
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_old), findsNothing); // and when it is opened again
      expect(find.text(_card), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets(
    'the answer lands while the entry is open again: its reflection goes',
    (t) async {
      final repo =
          _Answers([_offered])
            ..analysisFor = _reflection(_old)
            ..gate = Completer<void>();
      final e = repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_old), findsOneWidget); // not answered yet

      repo.gate!.complete();
      await t.pumpAndSettle();
      expect(find.text(_old), findsNothing);
      expect(find.text(_card), findsOneWidget);
      expect(
        _container(t).read(journalEntryDetailProvider(e.id)).value!.analysis,
        isNull,
      );
    },
  );

  testWidgets(
    'PF-C7: a later fresh reflection puts the card away and is shown',
    (t) async {
      final repo = _Answers([
        _offered,
        {
          'status': 'completed',
          'tone': 'heavy',
          'observation': 'A new reflection.',
          'confidence': 'low',
        },
      ])..analysisFor = _reflection(_old);
      repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      expect(find.text(_card), findsOneWidget);

      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      repo.analysisFor = _reflection('A new reflection.');
      await _type(t, 'Later, calmer words. ');
      await _back(t);
      await t.pumpAndSettle();
      expect(repo.analysed, hasLength(2));
      expect(find.text(_card), findsNothing); // dismissed by the answer

      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text('A new reflection.'), findsOneWidget);
      expect(find.text(_card), findsNothing);
    },
  );

  testWidgets(
    'PF-C7: any other answer puts the card away; the old reflection stays hidden',
    (t) async {
      final repo = _Answers([
        _offered,
        {'status': 'paused'},
      ])..analysisFor = _reflection(_old);
      repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      expect(find.text(_card), findsOneWidget);

      await _write(t, 'Tonight', 'Other words. ');
      expect(repo.analysed, hasLength(2));
      expect(find.text(_card), findsNothing);
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_old), findsNothing);
    },
  );

  testWidgets(
    'PF-C6: "Not now" on Patterns keeps it away for the run, never stored',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo = _Answers([]);
      repo.addEntry(title: 'One', text: 'x');
      await pumpJournal(t, repo: repo);
      await t.tap(find.text('Patterns'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      expect(find.text(_away), findsOneWidget);

      // Read again (as a later visit does): still away.
      final reads = repo.patternsReads;
      _container(t).invalidate(journalPatternsProvider);
      await t.pumpAndSettle();
      expect(repo.patternsReads, greaterThan(reads));
      expect(find.text(_card), findsNothing);
      await t.tap(find.text('Entries'));
      await t.pumpAndSettle();
      await t.tap(find.text('Patterns'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      expect(
        _container(t).read(journalPatternsSupportDismissedProvider),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.contains('support')), isEmpty);
    },
  );

  testWidgets('PF-C6: once the check no longer matches, the summary shows', (
    t,
  ) async {
    final repo = _Answers([]);
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    repo.patterns = 'completed';
    _container(t).invalidate(journalPatternsProvider);
    await t.pumpAndSettle();
    expect(find.text('A summary of your entries.'), findsOneWidget);
    expect(find.text(_away), findsNothing);
  });

  testWidgets('PF-C6: a new support_offered brings Patterns\' card back', (
    t,
  ) async {
    final repo = _Answers([_offered]);
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Entries'));
    await t.pumpAndSettle();
    await _write(t, 'One', 'Words the check reads as a crisis');
    await t.tap(find.text('Not now')); // the list's card
    await t.pumpAndSettle();
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsOneWidget);
  });

  testWidgets(
    'I-2: a summary read earlier gives way to the card after a crisis answer',
    (t) async {
      final repo =
          _Answers([_offered])
            ..patterns = 'completed'
            ..crisisMovesPatterns = true;
      repo.addEntry(title: 'One', text: 'x');
      await pumpJournal(t, repo: repo);
      await t.tap(find.text('Patterns'));
      await t.pumpAndSettle();
      expect(find.text('A summary of your entries.'), findsOneWidget);
      await t.tap(find.text('Entries'));
      await t.pumpAndSettle();
      await _write(t, 'One', 'Words the check reads as a crisis');
      await t.tap(find.text('Patterns'));
      await t.pumpAndSettle();
      expect(find.text('A summary of your entries.'), findsNothing);
      expect(find.text(_card), findsOneWidget);
    },
  );

  testWidgets('I-3: the list card shows for an entry beyond the first page', (
    t,
  ) async {
    final repo = _Answers([_offered]);
    final now = DateTime.now();
    for (var i = 0; i < 30; i++) {
      repo.addEntry(
        title: 'Recent $i',
        text: 'x',
        createdAt: now.subtract(Duration(minutes: i)),
      );
    }
    repo.addEntry(
      title: 'Old',
      text: '',
      createdAt: now.subtract(const Duration(days: 40)),
    );
    await pumpJournal(t, repo: repo);
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await t.scrollUntilVisible(find.text('Old'), 400, scrollable: list.first);
    await t.pumpAndSettle();
    await _write(t, 'Old', 'Words the check reads as a crisis');
    expect(repo.analysed, hasLength(1));
    bool oldListed() => _container(
      t,
    ).read(journalListProvider).value!.entries.any((e) => e.title == 'Old');
    expect(oldListed(), isFalse); // closing reloads page 1 only
    t.state<ScrollableState>(list.first).position.jumpTo(0);
    await t.pumpAndSettle();
    expect(oldListed(), isFalse); // still not on the list
    expect(find.text(_card), findsOneWidget);
  });

  testWidgets(
    'I-1 (D8): another account on the phone gets none of the first one\'s '
    'card, hidden reflections, Patterns "Not now" or list',
    (t) async {
      final repo = _TwoAccounts([_offered])..analysisFor = _reflection(_old);
      final mine = repo.addFor('ama', 'Ama entry');
      repo.addFor('kofi', 'Kofi entry');
      await pumpJournal(
        t,
        repo: repo,
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        ],
      );
      expect(find.text('Kofi entry'), findsNothing);
      await _write(t, 'Ama entry', 'Words the check reads as a crisis');
      expect(find.text(_card), findsOneWidget);
      await t.tap(find.text('Patterns'));
      await t.pumpAndSettle();
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      final c = _container(t);
      expect(c.read(journalHiddenReflectionsProvider), {mine.id});
      expect(c.read(journalPatternsSupportDismissedProvider), isTrue);

      await _switchTo(t, repo, null); // signed out
      await _switchTo(t, repo, 'kofi');
      expect(c.read(journalSupportOffersProvider), isEmpty);
      expect(c.read(journalHiddenReflectionsProvider), isEmpty);
      expect(c.read(journalPatternsSupportDismissedProvider), isFalse);
      // Kofi's own Patterns, read again for Kofi.
      expect(find.text('A summary of your entries.'), findsOneWidget);
      expect(find.text(_card), findsNothing);
      expect(find.text(_away), findsNothing);
      await t.tap(find.text('Entries'));
      await t.pumpAndSettle();
      expect(find.text(_card), findsNothing);
      expect(find.text('Ama entry'), findsNothing);
      expect(find.text('Kofi entry'), findsOneWidget);
      // N-3: Kofi's list sweeps Kofi's own expired deletes.
      expect(repo.sweptFor.last, 'kofi');
      expect(repo.sweptFor.first, 'ama');
    },
  );

  testWidgets(
    'I-1 (D8): the Conversations row never shows the last account\'s entry',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _TwoAccounts([]);
      repo.addFor('ama', 'Ama entry');
      repo.addFor('kofi', 'Kofi entry');
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
            reflectionJournalRepositoryProvider.overrideWithValue(repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            timeline.currentRelationshipIdProvider.overrideWith(
              (ref) async => null,
            ),
          ],
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder:
                (_, __) => const MaterialApp(
                  home: Scaffold(
                    body: SingleChildScrollView(child: JournalsCard()),
                  ),
                ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Ama entry'), findsOneWidget);
      await _switchTo(t, repo, null); // signed out
      await _switchTo(t, repo, 'kofi');
      expect(find.text('Ama entry'), findsNothing);
      expect(find.text('Kofi entry'), findsOneWidget);
    },
  );

  group('N-1 (D8): while the next account\'s first read is out', () {
    Widget journalsCard() => ScreenUtilInit(
      designSize: const Size(390, 844),
      builder:
          (_, __) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder:
                      (_, ref, __) =>
                          ref.watch(_rowShown)
                              ? const JournalsCard()
                              : const SizedBox(),
                ),
              ),
            ),
          ),
    );

    Future<_TwoAccounts> pumpRow(WidgetTester t) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = _TwoAccounts([]);
      repo.addFor('ama', 'Ama entry');
      repo.addFor('kofi', 'Kofi entry');
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
            reflectionJournalRepositoryProvider.overrideWithValue(repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            timeline.currentRelationshipIdProvider.overrideWith(
              (ref) async => null,
            ),
          ],
          child: journalsCard(),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Ama entry'), findsOneWidget);
      return repo;
    }

    testWidgets('the journal list never shows the last account\'s entries', (
      t,
    ) async {
      final repo = _TwoAccounts([]);
      repo.addFor('ama', 'Ama entry');
      repo.addFor('kofi', 'Kofi entry');
      await pumpJournal(
        t,
        repo: repo,
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        ],
      );
      expect(find.text('Ama entry'), findsOneWidget);
      await _switchHeld(t, _container(t), repo, 'kofi');
      expect(find.text('Ama entry'), findsNothing); // the read is still out
      expect(find.text('Kofi entry'), findsNothing);
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Kofi entry'), findsOneWidget);
      expect(find.text('Ama entry'), findsNothing);
    });

    testWidgets('the journal list shows an error, never A\'s list, when B\'s '
        'read fails', (t) async {
      final repo = _TwoAccounts([]);
      repo.addFor('ama', 'Ama entry');
      await pumpJournal(
        t,
        repo: repo,
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
        ],
      );
      await _switchHeld(t, _container(t), repo, 'kofi');
      repo.failHeld = true;
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Ama entry'), findsNothing);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets(
      'the Conversations row: loading, then failed: never A\'s title',
      (t) async {
        final repo = await pumpRow(t);
        final c = _container(t);
        await _switchHeld(t, c, repo, 'kofi');
        expect(find.text('Ama entry'), findsNothing);
        expect(find.text('Start your first reflection'), findsOneWidget);
        repo.failHeld = true;
        repo.hold!.complete();
        await t.pumpAndSettle();
        expect(find.text('Ama entry'), findsNothing);
        expect(find.text('Start your first reflection'), findsOneWidget);
      },
    );

    testWidgets('the Conversations row, away over sign-out, lands on B: '
        'never A\'s title', (t) async {
      final repo = await pumpRow(t);
      final c = _container(t);
      c.read(_rowShown.notifier).state = false; // sign-out leaves home
      await t.pumpAndSettle();
      await _switchTo(t, repo, null);
      await _switchHeld(t, c, repo, 'kofi');
      c.read(_rowShown.notifier).state = true; // B lands on Conversations
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Ama entry'), findsNothing);
      repo.hold!.complete();
      await t.pumpAndSettle();
      expect(find.text('Kofi entry'), findsOneWidget);
    });
  });

  group('N-2 (D8): a list read for the last account never lands', () {
    Future<(ProviderContainer, _TwoAccounts)> start() async {
      final repo = _TwoAccounts([]);
      final now = DateTime.now();
      for (var i = 0; i < 31; i++) {
        repo.addFor(
          'ama',
          'Ama $i',
          createdAt: now.subtract(Duration(minutes: i)),
        );
      }
      repo.addFor('kofi', 'Kofi entry');
      final c = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
          reflectionJournalRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(c.dispose);
      c.listen(journalListProvider, (_, __) {});
      final ama = await c.read(journalListProvider.future);
      expect(ama.hasMore, isTrue);
      return (c, repo);
    }

    Future<void> switchToKofi(ProviderContainer c, _TwoAccounts repo) async {
      repo.account = 'kofi';
      c.read(_signedIn.notifier).state = _user('kofi');
      final kofi = await c.read(journalListProvider.future);
      expect(kofi.entries.map((e) => e.title), ['Kofi entry']);
    }

    test('refresh', () async {
      final (c, repo) = await start();
      repo
        ..held = 'ama'
        ..hold = Completer<void>();
      final late = c.read(journalListProvider.notifier).refresh();
      await switchToKofi(c, repo);
      repo.hold!.complete();
      await late;
      expect(c.read(journalListProvider).value!.entries.map((e) => e.title), [
        'Kofi entry',
      ]);
    });

    test('loadMore', () async {
      final (c, repo) = await start();
      repo
        ..held = 'ama'
        ..hold = Completer<void>();
      final late = c.read(journalListProvider.notifier).loadMore();
      await switchToKofi(c, repo);
      repo.hold!.complete();
      await late;
      expect(c.read(journalListProvider).value!.entries.map((e) => e.title), [
        'Kofi entry',
      ]);
    });

    test('loadMore waits while the list is loading', () async {
      final (c, repo) = await start();
      repo
        ..held = 'kofi'
        ..hold = Completer<void>()
        ..account = 'kofi';
      c.read(_signedIn.notifier).state = _user('kofi');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(journalListProvider).isLoading, isTrue);
      final calls = repo.listCalls;
      await c.read(journalListProvider.notifier).loadMore();
      expect(repo.listCalls, calls); // nothing asked for A's next page
      repo.hold!.complete();
    });
  });

  testWidgets('N-3: a fresh reflection reads Patterns again', (t) async {
    final repo = _Answers([
      {
        'status': 'completed',
        'tone': 'heavy',
        'observation': 'A new reflection.',
        'confidence': 'low',
      },
    ])..patterns = 'completed';
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    final reads = repo.patternsReads;
    await t.tap(find.text('Entries'));
    await t.pumpAndSettle();
    await _write(t, 'One', 'Calm words. ');
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    expect(repo.patternsReads, reads + 1);
  });

  testWidgets('I-1 (D8): a late answer for the first account never lands', (
    t,
  ) async {
    final repo = _TwoAccounts([_offered])..gate = Completer<void>();
    repo.addFor('ama', 'Ama entry');
    repo.addFor('kofi', 'Kofi entry');
    await pumpJournal(
      t,
      repo: repo,
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(_signedIn)),
      ],
    );
    await _write(t, 'Ama entry', 'Words the check reads as a crisis');
    await _switchTo(t, repo, 'kofi');
    repo.gate!.complete();
    await t.pumpAndSettle();
    final c = _container(t);
    expect(c.read(journalSupportOffersProvider), isEmpty);
    expect(c.read(journalHiddenReflectionsProvider), isEmpty);
    expect(find.text(_card), findsNothing);
  });

  testWidgets('I-1/M-1: sign-out and quick exit empty the support state', (
    t,
  ) async {
    final repo = _Answers([_offered]);
    repo.addEntry(title: 'Tonight', text: '');
    await pumpJournal(t, repo: repo);
    await _write(t, 'Tonight', 'Words the check reads as a crisis');
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    final c = _container(t);
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final entry = registry.entries.firstWhere(
      (e) => e.id == 'spec1.journal_support_memory',
    );
    expect(entry.moments, {WipeMoment.signOut, WipeMoment.quickExit});
    expect(entry.keys, isEmpty);
    expect(entry.protective, isFalse);
    expect(c.read(journalSupportOffersProvider), isNotEmpty);
    await entry.run();
    await t.pumpAndSettle();
    expect(c.read(journalSupportOffersProvider), isEmpty);
    expect(c.read(journalHiddenReflectionsProvider), isEmpty);
    expect(c.read(journalPatternsSupportDismissedProvider), isFalse);
    await t.tap(find.text('Entries'));
    await t.pumpAndSettle();
    expect(find.text(_card), findsNothing);
  });

  testWidgets(
    'M-3: an older request\'s late answer never undoes a newer match',
    (t) async {
      final repo = _Answers([
        {
          'status': 'completed',
          'tone': 'heavy',
          'observation': 'A late reflection.',
          'confidence': 'low',
        },
        _offered,
      ])..analysisFor = _reflection(_old);
      final slow = Completer<void>();
      repo.gates[0] = slow;
      repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Calm words first. ');
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      expect(find.text(_card), findsOneWidget);
      slow.complete(); // the first visit's answer lands last
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget);
      await t.tap(find.text('Tonight'));
      await t.pumpAndSettle();
      expect(find.text(_old), findsNothing);
      expect(find.text(_card), findsOneWidget);
    },
  );

  testWidgets(
    'M-3: a match always applies, even when it is the older request\'s',
    (t) async {
      final repo = _Answers([
        _offered,
        {'status': 'paused'},
      ]);
      final slow = Completer<void>();
      repo.gates[0] = slow;
      repo.addEntry(title: 'Tonight', text: '');
      await pumpJournal(t, repo: repo);
      await _write(t, 'Tonight', 'Words the check reads as a crisis');
      await _write(t, 'Tonight', 'More words. ');
      expect(find.text(_card), findsNothing);
      slow.complete(); // the match lands last: fail safe, the card shows
      await t.pumpAndSettle();
      expect(find.text(_card), findsOneWidget);
    },
  );

  testWidgets('the card is one container for screen readers', (t) async {
    await pumpFlowScreen(
      t,
      () => Scaffold(body: JournalSupportCard(onNotNow: () {})),
    );
    expect(
      find.ancestor(
        of: find.text(_card),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.container),
      ),
      findsOneWidget,
    );
  });

  testWidgets('M-5: the away state lets large text through', (t) async {
    final repo = _Answers([]);
    repo.addEntry(title: 'One', text: 'x');
    await pumpJournal(t, repo: repo);
    await t.tap(find.text('Patterns'));
    await t.pumpAndSettle();
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(
      find.text('Your entries are saved and stay private to you.'),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text(_away),
        matching: find.byType(AllowLargeText),
      ),
      findsOneWidget,
    );
  });

  testWidgets('I-4: the manual passage needs no flag', (t) async {
    DocumentationRegistry.initialize();
    late BuildContext context;
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          documentationFlagsProvider.overrideWith((ref) async => <String>{}),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (c, ref, _) {
              ref.watch(documentationFlagsProvider);
              context = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final module = DocumentationRegistry.getById('reflectionJournal')!;
    final ids = [
      for (final s in module.getSections(context))
        for (final c in s.contents) c.id,
    ];
    expect(ids, contains('journal_support_first'));
  });

  for (final (name, theme) in [
    ('light', AppTheme.lightTheme),
    ('dark', AppTheme.darkTheme),
  ]) {
    testWidgets('the card meets the guidelines ($name)', (t) async {
      Widget card() => Theme(
        data: theme,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: JournalSupportCard(onNotNow: () {}),
          ),
        ),
      );
      await pumpFlowScreen(t, card);
      await expectFlowGuidelines(t);
      for (final label in ['Not now', 'See support']) {
        final size = t.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
    });
  }

  testWidgets('the card lets large text through the shell clamp', (t) async {
    await pumpFlowScreen(
      t,
      () => Scaffold(body: JournalSupportCard(onNotNow: () {})),
      textScale: 2.0,
    );
    expect(MediaQuery.textScalerOf(t.element(find.text(_card))).scale(10), 20);
    expect(
      MediaQuery.textScalerOf(t.element(find.text('See support'))).scale(10),
      20,
    );
  });

  testWidgets('the entry menu link is labelled and 48 dp', (t) async {
    final repo = FakeJournalRepository(now: DateTime.now());
    final e = repo.addEntry(title: 'Menu', text: 'x');
    await pumpJournal(
      t,
      repo: repo,
      initial: '/journalEntry',
      extra: JournalEntryArgs(entryId: e.id),
    );
    await t.tap(find.byTooltip('Entry options'));
    await t.pumpAndSettle();
    final tap = find.ancestor(
      of: find.text('Need support now?'),
      matching: find.byType(InkWell),
    );
    expect(t.getSize(tap.first).height, greaterThanOrEqualTo(48));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
  });
}
