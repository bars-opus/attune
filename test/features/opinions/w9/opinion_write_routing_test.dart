// Spec 1 W9a, owner ruling (b) 2026-11-04: every client create and edit of
// an opinion or a comment goes through the six writer RPCs migration 16
// filters, never a direct table write. The client reads no flag on these
// paths (the filter is gated server-side by opinions_safety_v1), so the
// flag-off path IS the flag-on path: these tests pin that each screen still
// calls today's repository method and each repository method still calls
// today's RPC. Delete (Spec 1 W9b, OPN-DELETE-RLS, ungated) calls
// remove_my_opinion / remove_my_comment: no direct write is left.
//
// Also pins the W9a refusal handling against a screen that closed while
// its write was in flight (ref is unusable after dispose).
import 'dart:async';
import 'dart:io';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/domain/content_filter_error.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:attune/features/opinions/presentation/screen/edit_opinion_screen.dart';
import 'package:attune/features/opinions/presentation/screen/opinion_compose_screen.dart';
import 'package:attune/features/opinions/presentation/screen/quote_compose_screen.dart';
import 'package:attune/features/opinions/presentation/widgets/content_filter_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/flow_harness.dart';
import 'support/fake_opinions.dart';
import '../../../helpers/tap_in_reach.dart';

class _Stop implements Exception {}

/// Records the first call the repository makes, then stops it.
class _FirstCall implements SupabaseClient {
  final calls = <String>[];

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #rpc) {
      calls.add(
        'rpc ${i.positionalArguments.first} ${i.namedArguments[#params]}',
      );
    } else {
      calls.add('${i.memberName}');
    }
    throw _Stop();
  }
}

/// Holds each write until [gate] completes, then refuses it.
class _HeldRepository extends FakeOpinionRepository {
  final gate = Completer<void>();

  Future<Never> _held() async {
    await gate.future;
    throw const PostgrestException(message: 'content:slur', code: '22023');
  }

  @override
  Future<void> createOpinion({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) => _held();

  @override
  Future<String> createQuoteOpinion({
    required String content,
    required String quotedOpinionId,
    List<String>? tagSlugs,
  }) => _held();

  @override
  Future<void> editOpinion({
    required String opinionId,
    required String content,
  }) => _held();
}

/// Refuses each post after a network-like delay, so a frame is drawn
/// between the tap and the refusal.
class _SlowRepository extends FakeOpinionRepository {
  @override
  Future<void> createOpinion({
    required String content,
    List<String>? pollOptions,
    List<String>? tagSlugs,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.createOpinion(
      content: content,
      pollOptions: pollOptions,
      tagSlugs: tagSlugs,
    );
  }
}

/// The writers migration 16 marks `-- Spec 1 W9a` (the filtered ones).
Set<String> _filteredWriters() {
  final sql =
      File(
        'supabase/migrations/20261104100000_opinion_content_filter.sql',
      ).readAsStringSync();
  final writers = <String>{};
  String? current;
  for (final line in sql.split('\n')) {
    final m = RegExp(
      r'^CREATE OR REPLACE FUNCTION public\.(\w+)\(',
    ).firstMatch(line);
    if (m != null) current = m.group(1);
    if (line.contains('-- Spec 1 W9a') && line.contains('PERFORM')) {
      writers.add(current!);
    }
  }
  return writers;
}

void main() {
  test('each repository write calls its filtered writer RPC first', () async {
    final rpcs = <String>{};
    Future<void> first(
      Future<void> Function(OpinionRepository r) write,
      String expected,
    ) async {
      final client = _FirstCall();
      await expectLater(
        write(OpinionRepository(client)),
        throwsA(isA<_Stop>()),
      );
      expect(client.calls, [expected]);
      rpcs.add(expected.split(' ')[1]);
    }

    await first(
      (r) => r.createOpinion(content: 'a'),
      'rpc create_opinion {p_content: a}',
    );
    await first(
      (r) => r.createOpinion(content: 'a', pollOptions: ['x', 'y']),
      'rpc create_opinion_with_poll {p_content: a, p_poll_options: [x, y]}',
    );
    await first(
      (r) => r.createQuoteOpinion(content: 'a', quotedOpinionId: 'o1'),
      'rpc create_opinion_with_quote {p_content: a, p_quoted_opinion_id: o1}',
    );
    await first(
      (r) => r.editOpinion(opinionId: 'o1', content: 'a'),
      'rpc edit_opinion {p_opinion_id: o1, p_content: a}',
    );
    await first(
      (r) => r.createComment(opinionId: 'o1', content: 'a', quotedText: 'q'),
      'rpc create_opinion_comment {p_opinion_id: o1, p_content: a, '
      'p_reply_to_comment_id: null, p_quoted_text: q}',
    );
    await first(
      (r) => r.editComment(commentId: 'c1', content: 'a'),
      'rpc edit_opinion_comment {p_comment_id: c1, p_content: a}',
    );
    // The six the client writes through are exactly the six the server
    // filters.
    expect(rpcs, _filteredWriters());
    expect(rpcs, hasLength(6));
  });

  test('each repository delete calls its remove_my_* RPC first', () async {
    Future<void> first(
      Future<void> Function(OpinionRepository r) write,
      String expected,
    ) async {
      final client = _FirstCall();
      await expectLater(
        write(OpinionRepository(client)),
        throwsA(isA<_Stop>()),
      );
      expect(client.calls, [expected]);
    }

    await first(
      (r) => r.deleteOpinion('o1'),
      'rpc remove_my_opinion {p_opinion_id: o1}',
    );
    await first(
      (r) => r.deleteComment('c1'),
      'rpc remove_my_comment {p_comment_id: c1}',
    );
  });

  test('no client code writes opinions or comments directly', () {
    final chain = RegExp(
      r"""\.from\(\s*['"](opinions|opinion_comments)['"]\s*\)([^;]*);""",
    );
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in chain.allMatches(f.readAsStringSync())) {
        final rest = m.group(2)!;
        expect(rest, isNot(contains('.insert(')), reason: f.path);
        expect(rest, isNot(contains('.upsert(')), reason: f.path);
        // Spec 1 W9b (OPN-DELETE-RLS): no soft delete by UPDATE (refused by
        // the SELECT policy) and no hard DELETE either.
        expect(rest, isNot(contains('.update(')), reason: f.path);
        expect(rest, isNot(contains('.delete(')), reason: f.path);
      }
    }
    // The scan itself works, whatever lib/ holds today (batch-3 review I-4).
    expect(
      chain.firstMatch("x.from('opinions').insert({'content': c});")?.group(2),
      contains('.insert('),
    );
    expect(
      chain
          .firstMatch(
            "x\n        .from('opinion_comments')\n        "
            ".update({'removed_at': t})\n        .eq('id', c);",
          )
          ?.group(2),
      contains('.update('),
    );
  });

  testWidgets('each screen still calls today\'s repository method', (
    tester,
  ) async {
    // Every write fails (not a filter refusal), so each screen stays put.
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(find.byType(TextFormField), 'A post long enough.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    await pumpOpinionScreen(
      tester,
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      repo: repo,
    );
    await tester.enterText(find.byType(TextFormField), 'A quote long enough.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    await pumpOpinionScreen(
      tester,
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      repo: repo,
    );
    await tester.enterText(find.byType(TextFormField), 'An edit long enough.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.writes, [
      'create:A post long enough.',
      'quote:A quote long enough.',
      'edit:An edit long enough.',
    ]);
  });

  testWidgets('the thread still calls today\'s repository methods', (
    tester,
  ) async {
    final repo = FakeOpinionRepository()..refuseWith = Exception('offline');
    final opinion = w9Opinion();
    await pumpOpinionScreen(
      tester,
      () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
      repo: repo,
    );
    await tester.enterText(find.byType(TextField).last, 'A comment.');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    await tapInReach(tester, find.byIcon(Icons.more_horiz).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'My own comment here.'),
      'My own comment, changed.',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.writes, [
      'comment:A comment.',
      'edit-comment:My own comment, changed.',
    ]);
  });

  final heldScreens = <String, (Widget Function(), String, String)>{
    'compose': (
      () => const OpinionComposeScreen(),
      'Post',
      'A post long enough.',
    ),
    'quote': (
      () => QuoteComposeScreen(quotedOpinion: w9Opinion()),
      'Post',
      'A quote long enough.',
    ),
    'edit': (
      () => EditOpinionScreen(opinion: w9Opinion(mine: true)),
      'Save',
      'An edit long enough.',
    ),
  };
  for (final MapEntry(key: name, value: (screen, button, text))
      in heldScreens.entries) {
    testWidgets('$name: a refusal after the screen closed throws nothing', (
      tester,
    ) async {
      final repo = _HeldRepository();
      final h = await pumpOpinionScreen(tester, screen, repo: repo);
      await tester.enterText(find.byType(TextFormField), text);
      await tester.pumpAndSettle();
      await tester.tap(find.text(button));
      await tester.pump();
      await tester.pumpWidget(const SizedBox()); // the screen closes
      repo.gate.complete();
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Counted all the same (batch-3 review M-3): the counter is read
      // before the write.
      expect(h.metrics, ['opinion_blocked:slur']);
    });
  }

  testWidgets('the refusal is announced, and again when the reason changes', (
    tester,
  ) async {
    final said = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final event = message as Map<Object?, Object?>;
        if (event['type'] == 'announce') {
          said.add(
            (event['data'] as Map<Object?, Object?>)['message'] as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        null,
      ),
    );
    final repo =
        _SlowRepository()
          ..refuseWith = const PostgrestException(
            message: 'content:contact_info',
            code: '22023',
          );
    await pumpOpinionScreen(
      tester,
      () => const OpinionComposeScreen(),
      repo: repo,
    );
    await tester.enterText(find.byType(TextFormField), 'A post long enough.');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post'));
    await tester.pump(); // a frame while the write is in flight
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    repo.refuseWith = const PostgrestException(
      message: 'content:explicit',
      code: '22023',
    );
    await tester.tap(find.text('Post'));
    await tester.pump(); // a frame while the write is in flight
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    // The same reason again, nothing typed: announced again (review M-4).
    await tester.tap(find.text('Post'));
    await tester.pump(); // a frame while the write is in flight
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(said, [
      startsWith('Phone numbers, emails, links and usernames'),
      startsWith("Opinions doesn't allow sexual content."),
      startsWith("Opinions doesn't allow sexual content."),
    ]);
  });

  testWidgets('the notice re-announces when its reason or part changes', (
    tester,
  ) async {
    final said = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final event = message as Map<Object?, Object?>;
        if (event['type'] == 'announce') {
          said.add(
            (event['data'] as Map<Object?, Object?>)['message'] as String,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        null,
      ),
    );
    var reason = ContentFilterReason.slur;
    var part = ContentFilterPart.text;
    late StateSetter rebuild;
    await pumpFlowScreen(
      tester,
      () => Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return ContentFilterNotice(reason: reason, part: part);
          },
        ),
      ),
    );
    rebuild(() => reason = ContentFilterReason.contactInfo);
    await tester.pumpAndSettle();
    rebuild(() => part = ContentFilterPart.pollOption);
    await tester.pumpAndSettle();
    rebuild(() {}); // same reason and part: silent
    await tester.pumpAndSettle();
    expect(said, [
      startsWith('This includes a word'),
      startsWith('Phone numbers, emails'),
      allOf(
        startsWith('Phone numbers, emails'),
        endsWith("It's in one of your poll options."),
      ),
    ]);
  });

  testWidgets('the notice reads at 4.5:1 in the dark theme too', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => Theme(
        data: AppTheme.darkTheme,
        child: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ContentFilterNotice(reason: ContentFilterReason.slur),
          ),
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets(
    'the notice is announced once: no live region on top of the announce',
    (tester) async {
      // W9 final M-6: an explicit announce plus liveRegion is read twice by
      // TalkBack. The announce stays (it also covers iOS).
      await pumpFlowScreen(
        tester,
        () => const Scaffold(
          body: ContentFilterNotice(reason: ContentFilterReason.slur),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(ContentFilterNotice),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.liveRegion ?? false),
          ),
        ),
        findsNothing,
      );
    },
  );
}
