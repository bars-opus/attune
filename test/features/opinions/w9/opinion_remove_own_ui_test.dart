// Spec 1 W9b (OPN-DELETE-RLS, ungated; batch-5 carry): the switch from a
// direct write to remove_my_opinion / remove_my_comment changes nothing a
// person sees. In the thread, deleting your own comment from its menu drops
// it at once, and deleting your own post from the post menu closes the
// thread, as before. The real repository runs underneath (only the reads
// are faked) and sends exactly one RPC each time, with opinions_safety_v1
// off and on alike: the delete path reads no flag, so both runs make the
// same requests and leave the same screen. The server half (the same
// outcome, flag off and on) is section C of opinion_remove_own_contracts.sql.
import 'dart:convert';

import 'package:attune/features/opinions/data/repositories/opinion_repository.dart';
import 'package:attune/features/opinions/presentation/screen/comment_thread_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_opinions.dart';

/// Fake reads; deletes go through the real [OpinionRepository] to a server
/// that answers with [flagOn] as opinions_safety_v1 if anything asks.
class _RealDeletes extends FakeOpinionRepository {
  _RealDeletes({required bool flagOn}) {
    real = OpinionRepository(
      SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path} ${request.body}');
          if (request.url.path == '/rest/v1/feature_flags') {
            return http.Response(
              jsonEncode([
                {'key': 'opinions_safety_v1', 'enabled': flagOn},
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('', 204, request: request);
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    );
  }

  late final OpinionRepository real;
  final requests = <String>[];

  @override
  Future<void> deleteOpinion(String opinionId) => real.deleteOpinion(opinionId);

  @override
  Future<void> deleteComment(String commentId) => real.deleteComment(commentId);
}

/// A first page that opens the thread, so closing the thread lands here.
Widget _opener(Widget Function() thread) => Builder(
  builder:
      (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => thread())),
            child: const Text('open thread'),
          ),
        ),
      ),
);

String _screen(WidgetTester tester) => [
  for (final text in [
    'open thread',
    'Trust is built in small moments.',
    'My own comment here.',
    'Someone else wrote this.',
  ])
    '$text: ${find.text(text).evaluate().length}',
].join(', ');

void main() {
  testWidgets('deleting your own comment: same requests, same thread, '
      'opinions_safety_v1 off and on', (tester) async {
    final outcome = <bool, String>{};
    for (final flagOn in [false, true]) {
      final repo = _RealDeletes(flagOn: flagOn);
      final opinion = w9Opinion();
      await pumpOpinionScreen(
        tester,
        () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
        repo: repo,
      );
      // Top-level comments show newest first: mine is the first menu.
      await tester.tap(find.byIcon(Icons.more_horiz).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      outcome[flagOn] = '${repo.requests} | ${_screen(tester)}';
      // A fresh app for the next run (no provider state carried over).
      await tester.pumpWidget(const SizedBox());
    }
    expect(outcome[false], outcome[true]);
    expect(
      outcome[false],
      '[POST /rest/v1/rpc/remove_my_comment '
      '${jsonEncode({'p_comment_id': 'c-mine'})}] | '
      'open thread: 0, Trust is built in small moments.: 1, '
      'My own comment here.: 0, Someone else wrote this.: 1',
    );
  });

  testWidgets('deleting your own post: same requests, the thread closes, '
      'opinions_safety_v1 off and on', (tester) async {
    final outcome = <bool, String>{};
    for (final flagOn in [false, true]) {
      final repo = _RealDeletes(flagOn: flagOn);
      final opinion = w9Opinion(mine: true);
      await pumpOpinionScreen(
        tester,
        () => _opener(
          () => CommentThreadScreen(opinionId: opinion.id, opinion: opinion),
        ),
        repo: repo,
      );
      await tester.tap(find.text('open thread'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      outcome[flagOn] = '${repo.requests} | ${_screen(tester)}';
      // A fresh app for the next run (no provider state carried over).
      await tester.pumpWidget(const SizedBox());
    }
    expect(outcome[false], outcome[true]);
    expect(
      outcome[false],
      '[POST /rest/v1/rpc/remove_my_opinion '
      '${jsonEncode({'p_opinion_id': 'o1'})}] | '
      'open thread: 1, Trust is built in small moments.: 0, '
      'My own comment here.: 0, Someone else wrote this.: 0',
    );
  });
}
