// lib/features/games/truth_or_dare/presentation/screens/custom_truth_or_dare_create_screen.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';



class CustomTruthOrDareCreateScreen extends ConsumerStatefulWidget {
  const CustomTruthOrDareCreateScreen({super.key});

  @override
  ConsumerState<CustomTruthOrDareCreateScreen> createState() =>
      _CustomTruthOrDareCreateScreenState();
}

class _CustomTruthOrDareCreateScreenState
    extends ConsumerState<CustomTruthOrDareCreateScreen> {
  final TextEditingController _contentController = TextEditingController();
  String _selectedType = 'truth';
  String _selectedTone = 'connecting';
  bool _isPrivate = true; // Private by default
  bool _isSubmitting = false;

  final List<String> _types = ['truth', 'dare'];
  final Map<String, String> _typeDisplay = {
    'truth': '🗣 Truth',
    'dare': '🎯 Dare',
  };
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
      _contentController.text.trim().isNotEmpty &&
      !_isSubmitting;

  Future<void> _saveQuestion() async {
    if (!_isValid) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(createCustomTruthOrDareQuestionProvider((
        questionType: _selectedType,
        content: _contentController.text.trim(),
        tone: _selectedTone,
        isPrivate: _isPrivate,
      )).future);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Question saved!')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
            // Type selector
            Text(
              'Type',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedType,
                  isExpanded: true,
                  items: _types.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_typeDisplay[type]!),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedType = value);
                  },
                ),
              ),
            ),
            Gap(Spacing.lg.h),

            // Content
            Text(
              _selectedType == 'truth' ? 'Question' : 'Dare instruction',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Gap(Spacing.sm.h),
            AppTextFormField(
              controller: _contentController,
              hintText: _selectedType == 'truth'
                  ? 'e.g., What is something you have never told anyone?'
                  : 'e.g., Send a voice note saying three things you love about your partner',
              maxLines: 4,
              maxLength: 200,
              // buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                  // null, 
                  label: '',
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
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.3),
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTone,
                  isExpanded: true,
                  items: _tones.map((tone) {
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
