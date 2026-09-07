import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/session_games/presentation/widgets/session_game_ui.dart';
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SessionGameQuestionCard(
            label: 'the situation',
            text: question.questionText,
          ),
          const SizedBox(height: 28),
          // `SessionGameQuestion.options` defaults to `const []`, so the
          // type system does not rule out an options-free scenario
          // question reaching this screen (e.g. a malformed server
          // response). Rather than render zero buttons and strand the
          // user with no way to proceed, show a plain unavailable message
          // -- no fabricated options, no auto-submit, no throw.
          if (question.options.isEmpty)
            Text(
              'This question is unavailable right now.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            )
          else ...[
            const SessionGameStageLabel(text: 'what would you do?'),
            const SizedBox(height: 14),
            for (final (index, option) in question.options.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SessionGameOptionCard(
                  text: option.text,
                  index: index,
                  onTap: () => onSubmit(option.key),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
