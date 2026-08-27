import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Captures this user's guess at their partner's current state (§8.4).
///
/// Guards against an empty submission locally so the user never sees the
/// server's rejection for something the UI could prevent. The 400-char
/// limit matches mirror_round_truth's own CHECK.
class MirrorQuestionScreen extends StatefulWidget {
  const MirrorQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  State<MirrorQuestionScreen> createState() => _MirrorQuestionScreenState();
}

class _MirrorQuestionScreenState extends State<MirrorQuestionScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            maxLength: 400,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What do you think they would say?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
