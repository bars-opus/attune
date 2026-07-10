import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingGuidedDateScreen extends ConsumerStatefulWidget {
  final String matchId;

  const DatingGuidedDateScreen({super.key, required this.matchId});

  @override
  ConsumerState<DatingGuidedDateScreen> createState() =>
      _DatingGuidedDateScreenState();
}

class _DatingGuidedDateScreenState
    extends ConsumerState<DatingGuidedDateScreen> {
  String? _selectedResponse;
  final TextEditingController _noteController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _conversationStarters = const [
    'What has felt grounding for you lately?',
    'What kind of encouragement actually lands for you?',
    'What does a genuinely restful weekend look like?',
    'What are you hoping to learn about someone as you date?',
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submitReflection() async {
    if (_selectedResponse == null || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ref.read(
        recordDateReflectionProvider((
          matchId: widget.matchId,
          response: _selectedResponse!,
          note:
              _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
        )).future,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reflection saved privately')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your reflection could not be saved.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('First date guide'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Safety resources',
            onPressed: () {
              Navigator.pushNamed(context, SafetyResourcesScreen.routeName);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conversation starters',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.md.h),
            ..._conversationStarters.map(
              (starter) => Padding(
                padding: EdgeInsets.only(bottom: Spacing.md.h),
                child: Container(
                  padding: EdgeInsets.all(Spacing.md.w),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(
                      BorderRadiusTokens.md.r,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline, size: 16),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: Text(starter, style: textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Gap(Spacing.lg.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keep it modest',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  Text(
                    'The Alignment preview is only a starting point. Curiosity matters more than trying to prove a fit on a first date.',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Gap(Spacing.lg.h),
            Container(
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safety support',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Gap(Spacing.sm.h),
                  const Text('Meet in a public place.'),
                  const Text('Share your plans with someone you trust.'),
                  const Text('Keep your own transport plan.'),
                  const Text('Leave if something feels off.'),
                  const Text(
                    'Never send money, bank details, or mobile-money transfers to someone you have not met, whatever the emergency.',
                  ),
                  Gap(Spacing.md.h),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Safety resources',
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              SafetyResourcesScreen.routeName,
                            );
                          },
                          size: ButtonSize.small,
                          customColor: colorScheme.surfaceContainerHighest,
                          textColor: colorScheme.onSurface,
                        ),
                      ),
                      Gap(Spacing.md.w),
                      Expanded(
                        child: AppButton(
                          label: 'Quick exit',
                          onPressed: () {
                            QuickExitService.execute(context);
                          },
                          size: ButtonSize.small,
                          customColor: colorScheme.error,
                          textColor: colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Gap(Spacing.xl.h),
            Text(
              'Private reflection',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Text(
              'This stays private to you and is not shared with your match or used in ranking.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            Gap(Spacing.md.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.sm.h,
              children: [
                _buildResponseChip(
                  context,
                  'meet_again',
                  'I would like to meet again',
                  colorScheme.primary,
                ),
                _buildResponseChip(
                  context,
                  'unsure',
                  'I am unsure',
                  Colors.orange,
                ),
                _buildResponseChip(
                  context,
                  'rather_not',
                  'I would rather not',
                  colorScheme.error,
                ),
              ],
            ),
            Gap(Spacing.md.h),
            AppTextFormField(
              controller: _noteController,
              label: 'Private note',
              hintText: 'Private note (optional)',
              maxLines: 3,
              maxLength: 500,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: 'Save reflection',
              onPressed:
                  _selectedResponse != null && !_isSubmitting
                      ? _submitReflection
                      : null,
              size: ButtonSize.medium,
              width: double.infinity,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponseChip(
    BuildContext context,
    String value,
    String label,
    Color color,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _selectedResponse == value;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedResponse = isSelected ? null : value;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: Spacing.md.w,
          vertical: Spacing.sm.h,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? color.withValues(alpha: 0.12)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
          border: Border.all(color: isSelected ? color : Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? color : null,
          ),
        ),
      ),
    );
  }
}
