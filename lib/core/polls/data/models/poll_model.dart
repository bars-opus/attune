// lib/core/polls/data/models/poll_model.dart

/// A poll attached to an opinion or a forum topic.
///
/// Spec: ATTUNE_MASTER_SPEC.md §8.11 "Polls". 2-4 options, plain text, fixed at
/// creation, never expires, one poll per post.
///
/// Results are hidden until the viewer votes. The server enforces that — when
/// [hasVoted] is false, `get_post_poll` returns NULL vote counts rather than
/// real ones, so a hidden standing is never present in the network response for
/// the client to leak. [PollOptionModel.voteCount] is therefore nullable, and
/// the null IS the hidden state.
class PollModel {
  final String id;

  /// Options in their fixed display order (`position` ascending).
  final List<PollOptionModel> options;

  /// The option this viewer voted for, or null if they have not voted.
  final String? myOptionId;

  /// Total votes across all options, or null while results are hidden. Masked
  /// server-side alongside the per-option counts, since a total narrows them.
  final int? totalVotes;

  const PollModel({
    required this.id,
    required this.options,
    this.myOptionId,
    this.totalVotes,
  });

  /// Whether this viewer has voted — the gate that reveals results.
  bool get hasVoted => myOptionId != null;

  /// Builds a poll from `get_post_poll`, which returns one row per option with
  /// the poll-level fields repeated on each row. Returns null for an empty
  /// result, which is the normal "this post has no poll" case.
  static PollModel? fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return null;

    final sorted = [...rows]..sort(
      (a, b) => (a['option_position'] as int? ?? 0).compareTo(b['option_position'] as int? ?? 0),
    );
    final first = sorted.first;

    return PollModel(
      id: first['poll_id'] as String,
      myOptionId: first['my_option_id'] as String?,
      totalVotes: first['total_votes'] as int?,
      options: sorted.map(PollOptionModel.fromRow).toList(),
    );
  }

  /// Mirrors [fromRows]'s keys so a cached poll round-trips through the same
  /// parser the live RPC path uses.
  List<Map<String, dynamic>> toRows() {
    return options
        .map(
          (option) => {
            'poll_id': id,
            'option_id': option.id,
            'option_position': option.position,
            'label': option.label,
            'vote_count': option.voteCount,
            'total_votes': totalVotes,
            'my_option_id': myOptionId,
            'has_voted': hasVoted,
          },
        )
        .toList();
  }

  /// Applies a vote locally so the UI can reveal results without a refetch.
  ///
  /// Mirrors `cast_poll_vote`'s counter arithmetic: moving a vote decrements the
  /// previous option and increments the new one; re-voting the same option is a
  /// no-op. Counts are null while hidden, so a first vote reveals them by
  /// treating the unknown prior counts as needing a server refresh — callers
  /// that need exact numbers on first vote should refetch instead.
  PollModel withVote(String optionId) {
    if (myOptionId == optionId) return this;

    final previous = myOptionId;
    final updated =
        options.map((option) {
          var count = option.voteCount;
          if (count != null) {
            if (option.id == previous) count = count > 0 ? count - 1 : 0;
            if (option.id == optionId) count = count + 1;
          }
          return option.copyWith(voteCount: count);
        }).toList();

    return PollModel(
      id: id,
      options: updated,
      myOptionId: optionId,
      // A first vote reveals results, but the true counts are only known
      // server-side — leave the total null so the UI refetches rather than
      // showing an invented number.
      totalVotes: previous == null ? null : totalVotes,
    );
  }

  /// Removes this viewer's vote, returning to the pre-vote (results hidden)
  /// state. Counts go back to null because hiding is what the server does.
  PollModel withoutVote() {
    return PollModel(
      id: id,
      options: options.map((o) => o.copyWith(voteCount: null)).toList(),
      myOptionId: null,
      totalVotes: null,
    );
  }
}

class PollOptionModel {
  final String id;

  /// Fixed display order. Arrives as `option_position` on the wire: Postgres
  /// rejects a bare `position` in a RETURNS TABLE declaration, which parses as
  /// a type context.
  final int position;

  final String label;

  /// Votes for this option, or null while results are hidden from this viewer.
  final int? voteCount;

  const PollOptionModel({
    required this.id,
    required this.position,
    required this.label,
    this.voteCount,
  });

  factory PollOptionModel.fromRow(Map<String, dynamic> json) {
    return PollOptionModel(
      id: json['option_id'] as String,
      position: json['option_position'] as int? ?? 0,
      label: json['label'] as String? ?? '',
      voteCount: json['vote_count'] as int?,
    );
  }

  PollOptionModel copyWith({int? voteCount}) {
    return PollOptionModel(
      id: id,
      position: position,
      label: label,
      voteCount: voteCount,
    );
  }

  /// Share of the total, 0.0-1.0, or null while results are hidden.
  double? shareOf(int? totalVotes) {
    final count = voteCount;
    if (count == null || totalVotes == null || totalVotes <= 0) return null;
    return count / totalVotes;
  }
}
