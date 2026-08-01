// lib/features/pulse/presentation/screens/weekly_checkin_screen.dart

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

class WeeklyCheckinScreen extends ConsumerStatefulWidget {
  const WeeklyCheckinScreen({super.key});

  @override
  ConsumerState<WeeklyCheckinScreen> createState() =>
      _WeeklyCheckinScreenState();
}

class _WeeklyCheckinScreenState extends ConsumerState<WeeklyCheckinScreen> {
  int? _communicationRating;
  int? _connectionRating;
  int? _conflictHealthRating;
  bool _conflictHealthNA = false;
  int? _alignmentRating;
  int? _safetyRating;
  bool _isSubmitting = false;

  bool get _allQuestionsAnswered {
    if (_communicationRating == null) return false;
    if (_connectionRating == null) return false;
    if (!_conflictHealthNA && _conflictHealthRating == null) return false;
    if (_alignmentRating == null) return false;
    if (_safetyRating == null) return false;
    return true;
  }

  Future<void> _submitCheckin() async {
    if (!_allQuestionsAnswered || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        submitWeeklyCheckinProvider((
          communicationRating: _communicationRating!,
          connectionRating: _connectionRating!,
          conflictHealthRating:
              _conflictHealthNA ? null : _conflictHealthRating,
          conflictHealthNA: _conflictHealthNA,
          alignmentRating: _alignmentRating!,
          safetyRating: _safetyRating!,
        )).future,
      );

      if (mounted) {
        context.pushReplacementNamed('checkinComplete');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to submit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final partnerName =
        ref.watch(partnerNameProvider).valueOrNull ?? 'your partner';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly check-in'),
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
            Text(
              'Week of ${_getCurrentWeekRange()}',
              style: textTheme.titleSmall?.copyWith(color: colorScheme.primary),
            ),
            Gap(Spacing.md.h),
            Text(
              'Five quick questions about your week with $partnerName.',
              style: textTheme.bodyMedium,
            ),
            Gap(Spacing.lg.h),
            Text(
              'Answer how it actually felt. There are no right or wrong answers.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontStyle: FontStyle.italic,
              ),
            ),
            Gap(Spacing.xl.h),

            // Question 1: Communication
            _buildQuestionCard(
              number: 1,
              title: 'Communication',
              question:
                  'How well did you and $partnerName express yourselves this week?',
              value: _communicationRating,
              onChanged:
                  (value) => setState(() => _communicationRating = value),
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),

            // Question 2: Connection
            _buildQuestionCard(
              number: 2,
              title: 'Connection',
              question: 'How close did you feel to $partnerName this week?',
              value: _connectionRating,
              onChanged: (value) => setState(() => _connectionRating = value),
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),

            // Question 3: Conflict Health
            _buildQuestionCard(
              number: 3,
              title: 'Conflict health',
              question:
                  'If there were any disagreements this week, how well did you handle them together?',
              value: _conflictHealthRating,
              onChanged:
                  (value) => setState(() => _conflictHealthRating = value),
              showNA: true,
              isNA: _conflictHealthNA,
              onNAToggled: (value) {
                setState(() {
                  final isChecked = value ?? false;
                  _conflictHealthNA = isChecked;
                  if (isChecked) _conflictHealthRating = null;
                });
              },
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),

            // Question 4: Alignment
            _buildQuestionCard(
              number: 4,
              title: 'Alignment',
              question:
                  'Did you and $partnerName feel like you are moving in the same direction?',
              value: _alignmentRating,
              onChanged: (value) => setState(() => _alignmentRating = value),
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.lg.h),

            // Question 5: Emotional Safety
            _buildQuestionCard(
              number: 5,
              title: 'Emotional safety',
              question:
                  'How safe did you feel being yourself with $partnerName this week?',
              value: _safetyRating,
              onChanged: (value) => setState(() => _safetyRating = value),
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
            Gap(Spacing.xl.h),

            // Submit button
            AppButton(
              label: 'Submit check-in',
              onPressed:
                  _allQuestionsAnswered && !_isSubmitting
                      ? _submitCheckin
                      : null,
              size: ButtonSize.large,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  String _getCurrentWeekRange() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    return '${startOfWeek.day} ${_getMonth(startOfWeek.month)} – ${endOfWeek.day} ${_getMonth(endOfWeek.month)}';
  }

  String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

Widget _buildQuestionCard({
  required int number,
  required String title,
  required String question,
  required int? value,
  required Function(int) onChanged,
  bool showNA = false,
  bool isNA = false,
  ValueChanged<bool?>? onNAToggled,
  required ColorScheme colorScheme,
  required TextTheme textTheme,
}) {
  return Container(
    padding: EdgeInsets.all(Spacing.md.w),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
      borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
            Gap(Spacing.sm.w),
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Gap(Spacing.md.h),
        Text(question, style: textTheme.bodyMedium),
        Gap(Spacing.lg.h),
        // 1-10 scale
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(10, (index) {
            final rating = index + 1;
            final isSelected = value == rating && !isNA;
            return GestureDetector(
              onTap: () => onChanged(rating),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected
                          ? colorScheme.primary.withOpacity(0.2)
                          : Colors.transparent,
                  border: Border.all(
                    color:
                        isSelected
                            ? colorScheme.primary
                            : colorScheme.outline.withOpacity(0.3),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '$rating',
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        Gap(Spacing.xs.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Poor', style: textTheme.labelSmall),
            Text('Excellent', style: textTheme.labelSmall),
          ],
        ),
        if (showNA) ...[
          Gap(Spacing.md.h),
          Row(
            children: [
              Checkbox(
                value: isNA,
                onChanged: onNAToggled,
                activeColor: colorScheme.primary,
              ),
              Text(
                'N/A — no disagreements this week',
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
