// lib/features/games/this_or_that/presentation/screens/custom_question_create_screen.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class CustomQuestionCreateScreen extends ConsumerStatefulWidget {
  const CustomQuestionCreateScreen({super.key});

  @override
  ConsumerState<CustomQuestionCreateScreen> createState() =>
      _CustomQuestionCreateScreenState();
}

class _CustomQuestionCreateScreenState
    extends ConsumerState<CustomQuestionCreateScreen> {
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _optionAController = TextEditingController();
  final TextEditingController _optionBController = TextEditingController();
  String? _selectedEmojiA;
  String? _selectedEmojiB;
  String _selectedTone = 'connecting';
  bool _isPrivate = false;
  bool _isSubmitting = false;

  final List<String> _tones = [
    'connecting',
    'romantic',
    'playful',
    'spicy',
    'intimate',
  ];

  final Map<String, String> _toneDisplay = {
    'connecting': '💙 Connecting',
    'romantic': '❤️ Romantic',
    'playful': '😄 Playful',
    'spicy': '🔥 Spicy',
    'intimate': '🌙 Intimate',
  };

  bool get _isValid =>
      _questionController.text.trim().isNotEmpty &&
      _optionAController.text.trim().isNotEmpty &&
      _optionBController.text.trim().isNotEmpty &&
      !_isSubmitting;

  Future<void> _saveQuestion() async {
    if (!_isValid) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        createCustomQuestionProvider((
          questionText: _questionController.text.trim(),
          optionA: _optionAController.text.trim(),
          optionB: _optionBController.text.trim(),
          emojiA: _selectedEmojiA,
          emojiB: _selectedEmojiB,
          tone: _selectedTone,
          isPrivate: _isPrivate,
        )).future,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Question saved!')));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _selectEmoji(bool isOptionA) async {
    const emojis = [
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

    final emoji = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Choose an emoji'),
            content: SizedBox(
              width: 300,
              height: 350,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  childAspectRatio: 1,
                ),
                itemCount: emojis.length,
                itemBuilder:
                    (context, index) => InkWell(
                      onTap: () => Navigator.pop(context, emojis[index]),
                      child: Center(
                        child: Text(
                          emojis[index],
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );

    if (emoji != null && mounted) {
      setState(() {
        if (isOptionA) {
          _selectedEmojiA = emoji;
        } else {
          _selectedEmojiB = emoji;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create custom question'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question
            Text(
              'Your question',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _questionController,
              hintText: 'e.g., What\'s your perfect Sunday?',
              maxLength: 100,
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
              // null,
              label: '',
            ),
            Gap(Spacing.lg.h),

            // Option A
            Text(
              'Option A',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: _optionAController,
                    hintText: 'e.g., Lazy morning at home',
                    maxLength: 50,
                    label: '',
                    // buildCounter:
                    //     (
                    //       context, {
                    //       required currentLength,
                    //       required isFocused,
                    //       maxLength,
                    //     }) => null,
                  ),
                ),
                Gap(Spacing.sm.w),
                GestureDetector(
                  onTap: () => _selectEmoji(true),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(
                        0.3,
                      ),
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md.r,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _selectedEmojiA ?? '🎲',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Gap(Spacing.lg.h),

            // Option B
            Text(
              'Option B',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Row(
              children: [
                Expanded(
                  child: AppTextFormField(
                    controller: _optionBController,
                    hintText: 'e.g., Adventure outdoors',
                    maxLength: 50,
                    label: '',
                    // buildCounter:
                    //     (
                    //       context, {
                    //       required currentLength,
                    //       required isFocused,
                    //       maxLength,
                    //     }) => null,
                  ),
                ),
                Gap(Spacing.sm.w),
                GestureDetector(
                  onTap: () => _selectEmoji(false),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withOpacity(
                        0.3,
                      ),
                      borderRadius: BorderRadius.circular(
                        BorderRadiusTokens.md.r,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _selectedEmojiB ?? '🎲',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Gap(Spacing.lg.h),

            // Tone selector
            Text(
              'Tone',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTone,
                  isExpanded: true,
                  items:
                      _tones.map((tone) {
                        return DropdownMenuItem(
                          value: tone,
                          child: Text(_toneDisplay[tone]!),
                        );
                      }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedTone = value);
                  },
                ),
              ),
            ),
            Gap(Spacing.lg.h),

            // Privacy setting
            Row(
              children: [
                Switch(
                  value: _isPrivate,
                  onChanged: (value) => setState(() => _isPrivate = value),
                  activeColor: colorScheme.primary,
                ),
                Gap(Spacing.sm.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPrivate ? 'Private' : 'Shared with partner',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _isPrivate
                            ? 'Only you can see and use this question'
                            : 'Your partner can see and use this question',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Gap(Spacing.xl.h),

            // Save button
            AppButton(
              label: 'Save question',
              onPressed: _isValid ? _saveQuestion : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}
