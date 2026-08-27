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
    required this.isSubject,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  /// Whether the viewer is this round's subject (Mirror only — always
  /// false for the other two games, which have no subject). Only Mirror
  /// reads it: the same seeded question is third-person, written for the
  /// guesser, so the subject needs different framing to know they are
  /// answering about themselves, not their partner. Sliding Scale and
  /// Scenario have no subject-vs-guesser distinction and ignore it.
  final bool isSubject;

  @override
  Widget build(BuildContext context) {
    switch (question.gameType) {
      case 'mirror':
        return MirrorQuestionScreen(
          question: question,
          onSubmit: onSubmit,
          isSubject: isSubject,
        );
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
