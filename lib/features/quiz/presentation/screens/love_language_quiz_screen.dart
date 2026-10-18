// lib/features/quiz/presentation/screens/love_language_quiz_screen.dart
//
// Spec 5 (R5-5): "What feels loving to me right now". One screen, five
// ratings and optional moments; it can be changed at any time, so there is
// no quiz progress to resume.

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/quiz/domain/models/love_language_result.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoveLanguageQuizScreen extends ConsumerStatefulWidget {
  const LoveLanguageQuizScreen({
    super.key,
    this.initial,
    this.save,
    this.onSaved,
  });

  /// The current answers, when changing them.
  final LoveLanguageResult? initial;

  /// Stores the answers; the default writes them for the signed-in person.
  final Future<void> Function(LoveLanguageResult result)? save;

  /// After a save; the default opens the result in place of this screen.
  final void Function(LoveLanguageResult result)? onSaved;

  @override
  ConsumerState<LoveLanguageQuizScreen> createState() =>
      _LoveLanguageQuizScreenState();
}

class _LoveLanguageQuizScreenState
    extends ConsumerState<LoveLanguageQuizScreen> {
  late final Map<LovingWay, LovingRating> _ratings = {
    ...?widget.initial?.ratings,
  };
  late final Set<LovingMoment> _moments = {...?widget.initial?.moments};
  bool _saving = false;

  Future<void> _save() async {
    final result = LoveLanguageResult(
      ratings: Map.of(_ratings),
      moments: Set.of(_moments),
      updatedAt: DateTime.now().toUtc(),
    );
    setState(() => _saving = true);
    try {
      final save = widget.save;
      if (save != null) {
        await save(result);
      } else {
        await ref.read(saveLoveLanguageResultProvider(result).future);
        ref.invalidate(userQuizzesStatusProvider);
      }
      if (!mounted) return;
      final onSaved = widget.onSaved;
      if (onSaved != null) {
        onSaved(result);
      } else {
        context.pushReplacementNamed('loveLanguageResult', extra: result);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't save. Try again.")),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('What feels loving')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(Spacing.lg.w),
          children: [
            Text(
              'What feels loving to you right now? Rate each one. You can '
              'change it any time.',
              style: textTheme.bodyLarge,
            ),
            Gap(Spacing.sm.h),
            Text(
              LoveLanguageResult.frameworkNote,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Gap(Spacing.lg.h),
            for (final way in LovingWay.values) ...[
              Text(way.label, style: textTheme.titleMedium),
              Gap(Spacing.sm.h),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<LovingRating>(
                  emptySelectionAllowed: true,
                  showSelectedIcon: false,
                  segments: [
                    for (final rating in LovingRating.values)
                      ButtonSegment(
                        value: rating,
                        label: Text(
                          rating.label,
                          key: ValueKey('loving-${way.key}-${rating.name}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  selected:
                      _ratings[way] == null
                          ? const <LovingRating>{}
                          : {_ratings[way]!},
                  onSelectionChanged:
                      (s) => setState(() {
                        if (s.isEmpty) {
                          _ratings.remove(way);
                        } else {
                          _ratings[way] = s.first;
                        }
                      }),
                ),
              ),
              Gap(Spacing.lg.h),
            ],
            Text('Especially (optional)', style: textTheme.titleMedium),
            Gap(Spacing.sm.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.sm.h,
              children: [
                for (final m in LovingMoment.values)
                  FilterChip(
                    label: Text(m.label),
                    selected: _moments.contains(m),
                    onSelected:
                        (on) => setState(
                          () => on ? _moments.add(m) : _moments.remove(m),
                        ),
                  ),
              ],
            ),
          ],
        ),
      ),
      // Always in reach, whatever the text size.
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          Spacing.lg.w,
          Spacing.sm.h,
          Spacing.lg.w,
          Spacing.lg.h,
        ),
        child: AppButton(
          label: 'Save',
          onPressed: _saving || _ratings.isEmpty ? null : _save,
          size: ButtonSize.medium,
        ),
      ),
    );
  }
}
