import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Presents a situation and its 3-4 response options (§8.4).
///
/// Submits the option KEY, not its display text: the server validates
/// the answer against the question's own option keys, so text would be
/// rejected. Options are rendered in their stored order and none is
/// styled as preferred — §8.4 is explicit that "neither option is
/// 'correct'", and visually privileging one would turn a diagnostic into
/// a test the user can fail.
class ScenarioQuestionScreen extends StatelessWidget {
  const ScenarioQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          for (final option in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onSubmit(option.key),
                  child: Text(option.text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
