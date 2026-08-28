import 'dart:io';

import 'package:attune/features/games/love_map/data/repositories/love_map_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoveMapRound', () {
    test('parses the subject from active_partner_id', () {
      final r = LoveMapRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': false,
        'active_partner_id': 'user-a',
      });
      expect(r.subjectId, 'user-a');
      expect(r.bothAnswered, isFalse);
    });

    test('a missing both_answered fails closed', () {
      final r = LoveMapRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'active_partner_id': null,
      });
      expect(
        r.bothAnswered,
        isFalse,
        reason: 'an absent gate flag must never read as revealed',
      );
    });

    test('carries no answer fields', () {
      // The §8.4 gate lives on the server, but a model with answer fields
      // invites a select() that reads around it. This pins the shape.
      final props = LoveMapRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': true,
        'active_partner_id': 'user-a',
      }).toString();
      expect(props.contains('answer'), isFalse);
    });
  });

  test('fetchOpenRounds selects no answer columns', () {
    // Reads the source rather than the runtime: the column list is the
    // guarantee, and a future edit adding answer_a here would bypass the
    // reveal gate without any test noticing.
    final src = File(
      'lib/features/games/love_map/data/repositories/love_map_repository.dart',
    ).readAsStringSync();
    final selectLine = RegExp(r"\.select\('([^']*round_number[^']*)'\)")
        .firstMatch(src)
        ?.group(1);

    expect(selectLine, isNotNull);
    expect(selectLine, contains('active_partner_id'));
    expect(selectLine, isNot(contains('answer_a')));
    expect(selectLine, isNot(contains('answer_b')));
  });
}
