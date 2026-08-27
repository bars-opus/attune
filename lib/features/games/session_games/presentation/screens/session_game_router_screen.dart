import 'package:attune/features/games/mirror/presentation/screens/mirror_question_screen.dart';
import 'package:attune/features/games/scenario/presentation/screens/scenario_question_screen.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
import 'package:flutter/material.dart';

/// Chooses the answer-input screen for a game type.
///
/// One router for all three: the games share waiting, reveal and end, and
/// differ only in how an answer is captured.
class SessionGameRouterScreen extends StatelessWidget {
  const SessionGameRouterScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    switch (question.gameType) {
      case 'mirror':
        return MirrorQuestionScreen(question: question, onSubmit: onSubmit);
      case 'scenario':
        return ScenarioQuestionScreen(question: question, onSubmit: onSubmit);
      case 'sliding_scale':
        return SlidingScaleQuestionScreen(
          question: question,
          onSubmit: onSubmit,
        );
      default:
        // An unknown type means seed data ran ahead of the client. Show a
        // plain message rather than a blank screen or a crash.
        return const Center(child: Text('This game is not available yet.'));
    }
  }
}
