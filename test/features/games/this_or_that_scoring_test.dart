import 'package:attune/features/games/this_or_that/domain/services/scoring_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _round({
  required int number,
  String? a,
  String? b,
  bool interesting = false,
}) => {
  'round_number': number,
  'answer_a': a,
  'answer_b': b,
  'is_interesting': interesting,
};

void main() {
  final scoring = ScoringService();

  group('the most interesting pick (THIS_OR_THAT.md §"deterministic")', () {
    test('is the first round where the two disagreed', () {
      final rounds = [
        _round(number: 1, a: 'left', b: 'left'),
        _round(number: 2, a: 'left', b: 'right'),
        _round(number: 3, a: 'right', b: 'left'),
      ];
      expect(scoring.getMostInterestingPick(rounds)['round_number'], 2);
    });

    test('an unanswered round is not a disagreement', () {
      // A null answer means the round was never played, not that the two
      // chose differently — surfacing it as "the most interesting pick"
      // would show an empty round as the highlight of the session.
      final rounds = [
        _round(number: 1, a: 'left', b: null),
        _round(number: 2, a: 'left', b: 'right'),
      ];
      expect(scoring.getMostInterestingPick(rounds)['round_number'], 2);
    });

    test('falls back to a flagged round when every round matched', () {
      final rounds = [
        _round(number: 1, a: 'left', b: 'left'),
        _round(number: 2, a: 'right', b: 'right', interesting: true),
        _round(number: 3, a: 'left', b: 'left'),
      ];
      expect(scoring.getMostInterestingPick(rounds)['round_number'], 2);
    });

    test('falls back to round 5 when nothing differs and nothing is flagged', () {
      final rounds = List.generate(
        8,
        (i) => _round(number: i + 1, a: 'left', b: 'left'),
      );
      expect(scoring.getMostInterestingPick(rounds)['round_number'], 5);
    });

    test('a short all-matching session falls back to its first round', () {
      final rounds = List.generate(
        3,
        (i) => _round(number: i + 1, a: 'left', b: 'left'),
      );
      expect(scoring.getMostInterestingPick(rounds)['round_number'], 1);
    });

    test('an empty session returns nothing rather than throwing', () {
      // rounds[0] on an empty list throws. The one caller happens to guard
      // against it, so this is a landmine rather than a live crash — but
      // the guard lives in a screen, three files away from the throw.
      expect(scoring.getMostInterestingPick(const []), isEmpty);
    });
  });

  group('match percentage', () {
    test('is a percentage of rounds played', () {
      expect(scoring.getMatchPercentage(3, 5), 60);
      expect(scoring.getMatchPercentage(5, 5), 100);
      expect(scoring.getMatchPercentage(0, 5), 0);
    });

    test('a zero-round session is 0%, not a divide by zero', () {
      expect(scoring.getMatchPercentage(0, 0), 0);
    });
  });
}
