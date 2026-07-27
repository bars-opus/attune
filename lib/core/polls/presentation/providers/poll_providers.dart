// lib/core/polls/presentation/providers/poll_providers.dart

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/polls/data/models/poll_model.dart';
import 'package:attune/core/polls/data/repositories/poll_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final pollRepositoryProvider = Provider<PollRepository>((ref) {
  return PollRepository(ref.watch(supabaseClientProvider));
});

/// Identifies which post a poll hangs off. Polls attach to an opinion OR a
/// forum topic, never both, so one provider family serves both surfaces.
class PollTarget {
  final String? opinionId;
  final String? topicId;

  const PollTarget.opinion(String this.opinionId) : topicId = null;
  const PollTarget.topic(String this.topicId) : opinionId = null;

  @override
  bool operator ==(Object other) =>
      other is PollTarget &&
      other.opinionId == opinionId &&
      other.topicId == topicId;

  @override
  int get hashCode => Object.hash(opinionId, topicId);
}

/// The poll attached to one post, or null when the post has none.
///
/// Results stay masked (null counts) until this viewer votes — the server does
/// the masking, so the hidden standing never reaches the client. After a vote or
/// a retraction this refetches rather than trusting local arithmetic, because
/// other people's votes land between renders and only the server knows the true
/// totals.
final pollProvider =
    AsyncNotifierProvider.family<PollNotifier, PollModel?, PollTarget>(
      PollNotifier.new,
    );

class PollNotifier extends FamilyAsyncNotifier<PollModel?, PollTarget> {
  @override
  Future<PollModel?> build(PollTarget arg) => _fetch();

  Future<PollModel?> _fetch() {
    final repo = ref.read(pollRepositoryProvider);
    final opinionId = arg.opinionId;
    return opinionId != null
        ? repo.getPollForOpinion(opinionId)
        : repo.getPollForTopic(arg.topicId!);
  }

  /// Casts or moves this viewer's vote.
  ///
  /// The option is applied optimistically so the bars animate immediately, then
  /// replaced by the server's counts. On failure the previous state is restored
  /// and the error rethrown for the caller to surface.
  Future<void> vote(String optionId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final previous = current;
    state = AsyncData(current.withVote(optionId));

    try {
      await ref.read(pollRepositoryProvider).castVote(optionId);
      state = AsyncData(await _fetch());
    } catch (error) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  /// Retracts this viewer's vote, re-hiding the results.
  Future<void> retract() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasVoted) return;

    final previous = current;
    state = AsyncData(current.withoutVote());

    try {
      await ref.read(pollRepositoryProvider).retractVote(current.id);
      state = AsyncData(await _fetch());
    } catch (error) {
      state = AsyncData(previous);
      rethrow;
    }
  }
}
