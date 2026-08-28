import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/games/love_map/data/repositories/love_map_repository.dart';
import 'package:attune/features/games/love_map/domain/love_map_selection.dart';
import 'package:attune/features/games/love_map/presentation/screens/love_map_question_screen.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final loveMapRepositoryProvider = Provider<LoveMapRepository>(
  (ref) => LoveMapRepository(),
);

const _genericError = 'Could not open your Love Map. Please try again.';

/// The Love Map itself: whichever prompts are currently open.
///
/// Deliberately not a session. §8.4 says Love Map "cannot be completed in
/// one session", so there is no game_sessions row, no waiting screen and no
/// end screen — just the prompts that are open right now.
class LoveMapScreen extends ConsumerStatefulWidget {
  const LoveMapScreen({super.key});

  @override
  ConsumerState<LoveMapScreen> createState() => _LoveMapScreenState();
}

class _LoveMapScreenState extends ConsumerState<LoveMapScreen> {
  bool _loading = true;
  String? _error;
  List<LoveMapRound> _rounds = const [];
  Map<String, LoveMapQuestion> _questions = const {};
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final userId = ref.read(currentUserProvider)?.id;
      final relationshipId =
          await ref.read(activeRelationshipIdProvider.future);
      if (!mounted) return;

      if (userId == null || relationshipId == null) {
        setState(() {
          _loading = false;
          _error = _genericError;
        });
        return;
      }

      final repo = ref.read(loveMapRepositoryProvider);
      final rounds = await repo.fetchOpenRounds(relationshipId);
      final open = rounds.where((r) => !r.bothAnswered).toList();
      final questions = await repo.fetchQuestions(
        open.map((r) => r.questionId).whereType<String>().toList(),
      );
      if (!mounted) return;

      setState(() {
        _rounds = open;
        _questions = {for (final q in questions) q.id: q};
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Never surface the raw error: it can carry row contents.
      setState(() {
        _loading = false;
        _error = _genericError;
      });
    }
  }

  Future<void> _submit(String answer) async {
    final round = _rounds[_index];
    try {
      await ref
          .read(loveMapRepositoryProvider)
          .submitAnswer(roundId: round.id, answer: answer);
    } catch (_) {
      // A returning user may have answered this prompt already; that is the
      // normal path, not a failure. Either way the prompt is behind them.
    }
    if (!mounted) return;
    setState(() => _index += 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(body: Center(child: Text(_error!)));
    }
    if (_index >= _rounds.length) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Nothing new right now. More prompts arrive each week.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final round = _rounds[_index];
    final question = _questions[round.questionId];
    if (question == null) {
      return const Scaffold(body: Center(child: Text(_genericError)));
    }

    final userId = ref.read(currentUserProvider)?.id;
    return LoveMapQuestionScreen(
      question: question,
      isSubject: round.subjectId != null && round.subjectId == userId,
      onSubmit: _submit,
    );
  }
}
