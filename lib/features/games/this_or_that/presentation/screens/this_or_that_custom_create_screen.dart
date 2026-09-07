import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_custom_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ThisOrThatCustomCreateScreen extends ConsumerStatefulWidget {
  const ThisOrThatCustomCreateScreen({super.key});

  @override
  ConsumerState<ThisOrThatCustomCreateScreen> createState() =>
      _ThisOrThatCustomCreateScreenState();
}

class _ThisOrThatCustomCreateScreenState
    extends ConsumerState<ThisOrThatCustomCreateScreen> {
  final _questionController = TextEditingController();
  final _optionAController = TextEditingController();
  final _optionBController = TextEditingController();

  String? _emojiA;
  String? _emojiB;
  String _tone = 'connecting';
  bool _isPrivate = true;
  bool _isSubmitting = false;

  static const _tones = <(String, String, IconData)>[
    ('connecting', 'Connecting', Icons.people_alt_rounded),
    ('romantic', 'Romantic', Icons.favorite_rounded),
    ('playful', 'Playful', Icons.celebration_rounded),
    ('spicy', 'Spicy', Icons.local_fire_department_rounded),
    ('intimate', 'Intimate', Icons.nights_stay_rounded),
  ];

  static const _emojis = <String>[
    '😀',
    '😂',
    '🥰',
    '😍',
    '🤔',
    '😎',
    '🔥',
    '💙',
    '❤️',
    '💚',
    '💛',
    '💜',
    '🍕',
    '🍔',
    '🌮',
    '🍣',
    '🥗',
    '🍩',
    '🏖️',
    '⛰️',
    '🌆',
    '🌃',
    '🎬',
    '📚',
    '🐕',
    '🐈',
    '🐦',
    '🐟',
    '🦋',
    '🌸',
    '🎮',
    '📱',
    '💻',
    '🎵',
    '🏀',
    '⚽',
  ];

  bool get _isValid =>
      _questionController.text.trim().isNotEmpty &&
      _optionAController.text.trim().isNotEmpty &&
      _optionBController.text.trim().isNotEmpty &&
      !_isSubmitting;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _questionController,
      _optionAController,
      _optionBController,
    ]) {
      controller.addListener(_draftChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _questionController,
      _optionAController,
      _optionBController,
    ]) {
      controller
        ..removeListener(_draftChanged)
        ..dispose();
    }
    super.dispose();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (!_isValid) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final request = (
      questionText: _questionController.text.trim(),
      optionA: _optionAController.text.trim(),
      optionB: _optionBController.text.trim(),
      emojiA: _emojiA,
      emojiB: _emojiB,
      tone: _tone,
      isPrivate: _isPrivate,
    );
    try {
      ref.invalidate(createThisOrThatCustomQuestionProvider(request));
      await ref.read(createThisOrThatCustomQuestionProvider(request).future);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your question could not be saved. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pickEmoji(bool forThis) async {
    final palette = ThisOrThatPalette.of(context);
    final emoji = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Give this choice a face',
                    style: Theme.of(
                      sheetContext,
                    ).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: _emojis.length,
                    itemBuilder:
                        (_, index) => InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap:
                              () => Navigator.pop(sheetContext, _emojis[index]),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.panel,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: palette.line),
                            ),
                            child: Center(
                              child: Text(
                                _emojis[index],
                                style: const TextStyle(fontSize: 26),
                              ),
                            ),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (emoji == null || !mounted) return;
    setState(() => forThis ? _emojiA = emoji : _emojiB = emoji);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      title: 'Write a question',
      scrollable: true,
      bottom: ThisOrThatPrimaryAction(
        label: 'Add to my deck',
        icon: Icons.add_rounded,
        loading: _isSubmitting,
        onPressed: _isValid ? _save : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ThisOrThatStageLabel(
              text: 'Make it yours',
              icon: Icons.edit_note_rounded,
              color: palette.thisColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'What should you both choose between?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Keep it clear, specific, and fun to reveal together.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          _QuestionDraft(controller: _questionController),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ChoiceDraft(
                  side: 'THIS',
                  controller: _optionAController,
                  emoji: _emojiA,
                  color: palette.thisColor,
                  surface: palette.thisSurface,
                  hint: 'Stay home',
                  onEmoji: () => _pickEmoji(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChoiceDraft(
                  side: 'THAT',
                  controller: _optionBController,
                  emoji: _emojiB,
                  color: palette.thatColor,
                  surface: palette.thatSurface,
                  hint: 'Head outside',
                  onEmoji: () => _pickEmoji(false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionLabel(text: 'MOOD', color: palette.mutedInk),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tone in _tones)
                ChoiceChip(
                  avatar: Icon(tone.$3, size: 17),
                  label: Text(tone.$2),
                  selected: _tone == tone.$1,
                  onSelected: (_) => setState(() => _tone = tone.$1),
                ),
            ],
          ),
          const SizedBox(height: 18),
          _PrivacyTile(
            isPrivate: _isPrivate,
            onChanged: (shared) => setState(() => _isPrivate = !shared),
          ),
        ],
      ),
    );
  }
}

class _QuestionDraft extends StatelessWidget {
  const _QuestionDraft({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(text: 'QUESTION', color: palette.mutedInk),
          TextField(
            controller: controller,
            maxLength: 100,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              height: 1.25,
              letterSpacing: 0,
            ),
            decoration: const InputDecoration(
              hintText: 'Perfect Sunday: stay home or head outside?',
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(top: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceDraft extends StatelessWidget {
  const _ChoiceDraft({
    required this.side,
    required this.controller,
    required this.emoji,
    required this.color,
    required this.surface,
    required this.hint,
    required this.onEmoji,
  });

  final String side;
  final TextEditingController controller;
  final String? emoji;
  final Color color;
  final Color surface;
  final String hint;
  final VoidCallback onEmoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _SectionLabel(text: side, color: color)),
              IconButton.outlined(
                tooltip: 'Choose an emoji',
                visualDensity: VisualDensity.compact,
                onPressed: onEmoji,
                icon: Text(emoji ?? '+', style: const TextStyle(fontSize: 18)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 3,
            maxLength: 50,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hint,
              counterText: '',
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  const _PrivacyTile({required this.isPrivate, required this.onChanged});

  final bool isPrivate;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          Icon(
            isPrivate
                ? Icons.lock_outline_rounded
                : Icons.people_outline_rounded,
            color: isPrivate ? palette.mutedInk : palette.thatColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPrivate ? 'Only me' : 'Share with my partner',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  isPrivate
                      ? 'You can still use it when choosing a card.'
                      : 'It appears in both of your question decks.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: palette.mutedInk,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: !isPrivate, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}
