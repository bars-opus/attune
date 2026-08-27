import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Captures either this user's guess at their partner's current state, or
/// (when they are the round's subject) their own real answer (§8.4).
///
/// Every seeded question is third-person, written for the guesser: "What
/// is weighing on them most this week?" The subject's job is the
/// opposite — report their OWN real state, which becomes the truth the
/// guess is scored against — so isSubject drives a second-person framing
/// on top of the same question text rather than a database column. The
/// seeded text still supplies the topic; what changes is making it
/// unmistakable that the subject is answering about themselves.
///
/// Guards against an empty submission locally so the user never sees the
/// server's rejection for something the UI could prevent. The 400-char
/// limit matches mirror_round_truth's own CHECK.
class MirrorQuestionScreen extends StatefulWidget {
  const MirrorQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
    required this.isSubject,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  /// True when the viewer is this round's subject — the one whose real
  /// inner state is being asked about, not the one guessing at it.
  final bool isSubject;

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
          if (widget.isSubject) ...[
            // Fixed second-person copy: the seeded question text below
            // is third-person and written for the guesser, so without
            // this the subject answers about their partner instead of
            // themselves, and that gets stored as the "truth" about
            // them.
            Text(
              'Answer honestly about yourself — your partner is trying '
              'to read you.',
              style: Theme.of(context).textTheme.labelLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
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
            decoration: InputDecoration(
              hintText: widget.isSubject
                  ? "What's actually true for you right now?"
                  : 'What do you think they would say?',
              border: const OutlineInputBorder(),
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
