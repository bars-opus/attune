// Sync audit I-8 follow-up: when a stored invite link is refused because the
// person is already in a relationship (active or paused), they are told why,
// instead of the link vanishing without a word.
import 'dart:io';

import 'package:attune/features/relationships/data/relationship_invite_service.dart';
import 'package:attune/features/relationships/presentation/open_relationship_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _server =
    "You're already in a relationship on Attune. End it first to join a new one.";

void main() {
  test('the refusal is recognised, with the server\'s words', () {
    final e = inviteAcceptFailure(
      const FunctionException(status: 409, details: {'error': _server}),
    );
    expect(e.alreadyInRelationship, isTrue);
    expect(e.retryable, isFalse);
    expect(e.message, _server);
  });

  test('other refusals are not', () {
    final selfAccept = inviteAcceptFailure(
      const FunctionException(
        status: 409,
        details: {'error': 'You cannot accept your own invite'},
      ),
    );
    expect(selfAccept.alreadyInRelationship, isFalse);
    expect(
      inviteAcceptFailure(const FunctionException(status: 503)).retryable,
      isTrue,
    );
    expect(inviteAcceptFailure(Exception('offline')).retryable, isTrue);
  });

  testWidgets('the notice shows the message', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showOpenRelationshipNotice(ctx, _server);
    await tester.pump();
    expect(find.text(_server), findsOneWidget);
  });

  test('both auto-accept paths tell the person', () {
    for (final path in [
      'lib/home/home_screen.dart',
      'lib/features/onboarding/presentation/screens/onboarding_gate.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, contains('alreadyInRelationship'), reason: path);
      expect(src, contains('showOpenRelationshipNotice('), reason: path);
    }
  });
}
