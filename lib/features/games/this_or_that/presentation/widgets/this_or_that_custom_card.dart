import 'package:attune/features/games/this_or_that/data/models/custom_this_or_that_question.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThisOrThatCustomCard extends ConsumerStatefulWidget {
  const ThisOrThatCustomCard({
    super.key,
    required this.question,
    required this.isOwnQuestion,
    this.onDeleted,
    this.onPrivacyChanged,
    this.onSharedChanged,
    this.onReported,
  });

  final CustomThisOrThatQuestion question;
  final bool isOwnQuestion;
  final VoidCallback? onDeleted;
  final VoidCallback? onPrivacyChanged;
  final VoidCallback? onSharedChanged;
  final VoidCallback? onReported;

  @override
  ConsumerState<ThisOrThatCustomCard> createState() =>
      _ThisOrThatCustomCardState();
}

class _ThisOrThatCustomCardState extends ConsumerState<ThisOrThatCustomCard> {
  bool _busy = false;

  CustomThisOrThatQuestion get question => widget.question;

  Future<void> _run(
    Future<void> Function() operation,
    VoidCallback? onSuccess,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      onSuccess?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That change did not go through. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Delete this question?'),
            content: const Text(
              'It will disappear from both question decks. Past game reveals stay unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep it'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () =>
          ref.read(deleteThisOrThatCustomQuestionProvider(question.id).future),
      widget.onDeleted,
    );
  }

  Future<void> _togglePrivacy() {
    return _run(
      () => ref.read(
        toggleThisOrThatCustomPrivacyProvider((
          id: question.id,
          isPrivate: !question.isPrivate,
        )).future,
      ),
      widget.onPrivacyChanged,
    );
  }

  Future<void> _toggleCommunity() async {
    if (!question.sharedToCommunity) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Share anonymously?'),
              content: const Text(
                'Other Attune couples may see this question. Your identity is never attached.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Share'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _run(
      () => ref.read(
        toggleThisOrThatCommunityShareProvider((
          id: question.id,
          share: !question.sharedToCommunity,
        )).future,
      ),
      widget.onSharedChanged,
    );
  }

  Future<void> _report() async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why are you reporting this?',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  for (final reason in const <(String, String)>[
                    ('inappropriate', 'Inappropriate content'),
                    ('hate_speech', 'Hate speech'),
                    ('wrong_tone', 'Too explicit for its tone'),
                    ('other', 'Something else'),
                  ])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(reason.$2),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(sheetContext, reason.$1),
                    ),
                ],
              ),
            ),
          ),
    );
    if (reason == null || !mounted) return;
    await _run(
      () => ref.read(
        reportThisOrThatCustomQuestionProvider((
          id: question.id,
          reason: reason,
        )).future,
      ),
      widget.onReported,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    _StatusLabel(
                      icon: _toneIcon(question.tone),
                      text: _toneLabel(question.tone),
                      color: palette.thatColor,
                    ),
                    if (question.isPrivate)
                      _StatusLabel(
                        icon: Icons.lock_outline_rounded,
                        text: 'Only me',
                        color: palette.mutedInk,
                      )
                    else
                      _StatusLabel(
                        icon: Icons.people_outline_rounded,
                        text: 'With partner',
                        color: palette.thisColor,
                      ),
                    if (question.sharedToCommunity)
                      _StatusLabel(
                        icon: Icons.public_rounded,
                        text: 'Community',
                        color: palette.thisColor,
                      ),
                  ],
                ),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<_QuestionAction>(
                  tooltip: 'Question actions',
                  onSelected: (action) {
                    switch (action) {
                      case _QuestionAction.privacy:
                        _togglePrivacy();
                        break;
                      case _QuestionAction.community:
                        _toggleCommunity();
                        break;
                      case _QuestionAction.delete:
                        _delete();
                        break;
                      case _QuestionAction.report:
                        _report();
                        break;
                    }
                  },
                  itemBuilder:
                      (_) =>
                          widget.isOwnQuestion
                              ? [
                                PopupMenuItem(
                                  value: _QuestionAction.privacy,
                                  child: Text(
                                    question.isPrivate
                                        ? 'Share with partner'
                                        : 'Make private',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _QuestionAction.community,
                                  child: Text(
                                    question.sharedToCommunity
                                        ? 'Remove from community'
                                        : 'Share anonymously',
                                  ),
                                ),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                  value: _QuestionAction.delete,
                                  child: Text('Delete'),
                                ),
                              ]
                              : const [
                                PopupMenuItem(
                                  value: _QuestionAction.report,
                                  child: Text('Report question'),
                                ),
                              ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            question.questionText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuestionOption(
                  side: 'THIS',
                  text: question.optionA,
                  emoji: question.emojiA,
                  color: palette.thisColor,
                  surface: palette.thisSurface,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuestionOption(
                  side: 'THAT',
                  text: question.optionB,
                  emoji: question.emojiB,
                  color: palette.thatColor,
                  surface: palette.thatSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Played ${question.timesUsed} ${question.timesUsed == 1 ? 'time' : 'times'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: palette.mutedInk,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  String _toneLabel(String tone) =>
      tone.isEmpty
          ? 'Connecting'
          : '${tone[0].toUpperCase()}${tone.substring(1)}';

  IconData _toneIcon(String tone) {
    switch (tone) {
      case 'romantic':
        return Icons.favorite_rounded;
      case 'playful':
        return Icons.celebration_rounded;
      case 'spicy':
        return Icons.local_fire_department_rounded;
      case 'intimate':
        return Icons.nights_stay_rounded;
      default:
        return Icons.people_alt_rounded;
    }
  }
}

enum _QuestionAction { privacy, community, delete, report }

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionOption extends StatelessWidget {
  const _QuestionOption({
    required this.side,
    required this.text,
    required this.emoji,
    required this.color,
    required this.surface,
  });

  final String side;
  final String text;
  final String? emoji;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            side,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${emoji?.isNotEmpty == true ? '$emoji ' : ''}$text',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
