import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rows shaped like get_post_poll's result: poll-level fields repeat on every
/// option row, and vote counts come back NULL until the viewer has voted.
List<Map<String, dynamic>> _rows({
  String? myOptionId,
  int? totalVotes,
  List<int?>? counts,
  List<String> labels = const ['Yes', 'No'],
}) {
  // Default to hidden counts (one null per label), matching what the server
  // returns before the viewer has voted.
  final resolved = counts ?? List<int?>.filled(labels.length, null);
  return [
    for (var i = 0; i < labels.length; i++)
      {
        'poll_id': 'poll-1',
        'option_id': 'opt-$i',
        'option_position': i,
        'label': labels[i],
        'vote_count': resolved[i],
        'total_votes': totalVotes,
        'my_option_id': myOptionId,
        'has_voted': myOptionId != null,
      },
  ];
}

void main() {
  group('PollModel.fromRows', () {
    test('returns null for an empty result, meaning "post has no poll"', () {
      expect(PollModel.fromRows(const []), isNull);
    });

    test('parses poll-level fields off the first row', () {
      final poll = PollModel.fromRows(
        _rows(myOptionId: 'opt-1', totalVotes: 7, counts: [3, 4]),
      )!;

      expect(poll.id, 'poll-1');
      expect(poll.myOptionId, 'opt-1');
      expect(poll.totalVotes, 7);
      expect(poll.options, hasLength(2));
    });

    test('orders options by position regardless of row order', () {
      final scrambled = _rows(labels: ['A', 'B', 'C']).reversed.toList();

      final poll = PollModel.fromRows(scrambled)!;

      expect(poll.options.map((o) => o.label), ['A', 'B', 'C']);
      expect(poll.options.map((o) => o.position), [0, 1, 2]);
    });

    test('hasVoted is false and counts stay null before voting', () {
      // The server masks counts until you vote — the null IS the hidden state,
      // so a client must never see a number here.
      final poll = PollModel.fromRows(_rows())!;

      expect(poll.hasVoted, isFalse);
      expect(poll.totalVotes, isNull);
      expect(poll.options.every((o) => o.voteCount == null), isTrue);
    });

    test('hasVoted is true once my_option_id is present', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 2, counts: [2, 0]),
          )!;

      expect(poll.hasVoted, isTrue);
    });
  });

  group('PollModel.withVote', () {
    test('records the choice and reveals results on a first vote', () {
      final poll = PollModel.fromRows(_rows())!;

      final voted = poll.withVote('opt-1');

      expect(voted.myOptionId, 'opt-1');
      expect(voted.hasVoted, isTrue);
    });

    test('leaves the total null on a first vote rather than inventing one', () {
      // Counts were hidden, so the true totals are unknown client-side. Showing
      // an invented number would be worse than waiting for the refetch.
      final poll = PollModel.fromRows(_rows())!;

      expect(poll.withVote('opt-0').totalVotes, isNull);
    });

    test('moves the count from the old option to the new one', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 10, counts: [6, 4]),
          )!;

      final moved = poll.withVote('opt-1');

      expect(moved.myOptionId, 'opt-1');
      expect(moved.options[0].voteCount, 5);
      expect(moved.options[1].voteCount, 5);
      // Moving a vote does not change how many votes exist.
      expect(moved.totalVotes, 10);
    });

    test('re-voting the same option is a no-op, never a double count', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 10, counts: [6, 4]),
          )!;

      final again = poll.withVote('opt-0');

      expect(again.options[0].voteCount, 6);
      expect(again.totalVotes, 10);
      expect(identical(again, poll), isTrue);
    });

    test('never drives a count below zero', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 1, counts: [0, 1]),
          )!;

      final moved = poll.withVote('opt-1');

      expect(moved.options[0].voteCount, 0);
    });
  });

  group('PollModel.withoutVote', () {
    test('re-hides results, matching what the server returns after retract', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 10, counts: [6, 4]),
          )!;

      final retracted = poll.withoutVote();

      expect(retracted.hasVoted, isFalse);
      expect(retracted.myOptionId, isNull);
      expect(retracted.totalVotes, isNull);
      expect(retracted.options.every((o) => o.voteCount == null), isTrue);
    });

    test('keeps the options themselves intact', () {
      final poll =
          PollModel.fromRows(
            _rows(myOptionId: 'opt-0', totalVotes: 10, counts: [6, 4]),
          )!;

      final retracted = poll.withoutVote();

      expect(retracted.options.map((o) => o.label), ['Yes', 'No']);
      expect(retracted.options.map((o) => o.id), ['opt-0', 'opt-1']);
    });
  });

  group('PollOptionModel.shareOf', () {
    test('returns the fraction of the total', () {
      const option = PollOptionModel(
        id: 'o',
        position: 0,
        label: 'Yes',
        voteCount: 3,
      );

      expect(option.shareOf(12), 0.25);
    });

    test('is null while the count is hidden', () {
      const option = PollOptionModel(id: 'o', position: 0, label: 'Yes');

      expect(option.shareOf(12), isNull);
    });

    test('is null when the total is unknown', () {
      const option = PollOptionModel(
        id: 'o',
        position: 0,
        label: 'Yes',
        voteCount: 3,
      );

      expect(option.shareOf(null), isNull);
    });

    test('is null rather than dividing by zero on an unvoted poll', () {
      const option = PollOptionModel(
        id: 'o',
        position: 0,
        label: 'Yes',
        voteCount: 0,
      );

      expect(option.shareOf(0), isNull);
    });
  });

  group('round-trip through toRows', () {
    test('survives a full encode/decode with results revealed', () {
      final original =
          PollModel.fromRows(
            _rows(
              myOptionId: 'opt-1',
              totalVotes: 9,
              counts: [4, 5],
              labels: ['Stay', 'Go'],
            ),
          )!;

      final restored = PollModel.fromRows(original.toRows())!;

      expect(restored.id, original.id);
      expect(restored.myOptionId, 'opt-1');
      expect(restored.totalVotes, 9);
      expect(restored.options.map((o) => o.label), ['Stay', 'Go']);
      expect(restored.options.map((o) => o.voteCount), [4, 5]);
    });

    test('preserves the hidden state, so a cached poll cannot leak counts', () {
      final hidden = PollModel.fromRows(_rows())!;

      final restored = PollModel.fromRows(hidden.toRows())!;

      expect(restored.hasVoted, isFalse);
      expect(restored.totalVotes, isNull);
      expect(restored.options.every((o) => o.voteCount == null), isTrue);
    });
  });
}
