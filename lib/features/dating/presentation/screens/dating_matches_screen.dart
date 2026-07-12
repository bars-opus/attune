import 'package:attune/core/ui/motion/glow_pulse.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:attune/features/dating/presentation/screens/dating_guided_date_screen.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingMatchesScreen extends ConsumerWidget {
  const DatingMatchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(datingMatchesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your matches'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Quick exit',
            onPressed: () => QuickExitService.execute(context),
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Safety resources',
            onPressed: () {
              Navigator.pushNamed(context, SafetyResourcesScreen.routeName);
            },
          ),
        ],
      ),
      body: matchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (error, stack) => const Center(
              child: Text(
                'Matches are unavailable right now. Please try again.',
              ),
            ),
        data: (matches) {
          if (matches.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(Spacing.xl.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.favorite_border_outlined,
                      size: 64,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                    Gap(Spacing.md.h),
                    Text('No matches yet', style: textTheme.titleMedium),
                    Gap(Spacing.sm.h),
                    Text(
                      'A match appears only after both people privately express interest.',
                      style: textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.all(Spacing.md.w),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              // A match is the feature's warmest moment — cards settle in with a
              // short per-index cascade. Reduce-motion safe.
              return SettleIn(
                key: ValueKey('match_${matches[index]['id']}'),
                duration:
                    const Duration(milliseconds: 280) +
                    Duration(milliseconds: 70 * index),
                child: _buildMatchCard(context, matches[index], ref),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMatchCard(
    BuildContext context,
    Map<String, dynamic> match,
    WidgetRef ref,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final displayName = match['display_name'] as String? ?? 'New match';
    final cityRegionCode = match['city_region_code'] as String?;
    final matchId = match['id'] as String;

    // Every card here is a mutual match — the celebratory state. A gentle glow
    // settles to a soft resting highlight (not a persistent flash), marking it
    // as special without urgency. Reduce-motion safe (GlowPulse settles static).
    return GlowPulse(
      active: true,
      color: colorScheme.primary,
      child: Container(
        margin: EdgeInsets.only(bottom: Spacing.md.h),
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                  child: Text(
                    displayName.isEmpty ? 'A' : displayName.characters.first,
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: textTheme.titleMedium),
                      Text(
                        [
                          if (cityRegionCode != null &&
                              cityRegionCode.isNotEmpty)
                            cityRegionCode,
                          'Matched ${_formatDate(DateTime.parse(match['matched_at'] as String))}',
                        ].join(' • '),
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Gap(Spacing.md.h),
            Text(
              'Dating chat safety review is still a production gate, so this build keeps the match actions focused on planning and safety rather than opening a full chat surface.',
              style: textTheme.bodySmall,
            ),
            Gap(Spacing.md.h),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'First date guide',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => DatingGuidedDateScreen(
                                matchId: match['id'] as String,
                              ),
                        ),
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
              ],
            ),
            Gap(Spacing.md.h),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Unmatch',
                    onPressed: () {
                      _showUnmatchConfirmation(
                        context,
                        ref,
                        match['id'] as String,
                      );
                    },
                    size: ButtonSize.small,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.error,
                  ),
                ),
                Gap(Spacing.md.w),
                Expanded(
                  child: AppButton(
                    label: 'Block',
                    onPressed: () {
                      _showBlockConfirmation(
                        context,
                        ref,
                        matchId,
                        displayName,
                      );
                    },
                    size: ButtonSize.small,
                    customColor: colorScheme.surfaceContainerHighest,
                    textColor: colorScheme.error,
                  ),
                ),
              ],
            ),
            Gap(Spacing.sm.h),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  _showReportDialog(context, ref, matchId, displayName);
                },
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Report'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    return 'just now';
  }

  void _showUnmatchConfirmation(
    BuildContext context,
    WidgetRef ref,
    String matchId,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Unmatch?'),
            content: const Text(
              'This ends the match. It does not notify the other person why.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(unmatchDatingProvider(matchId).future);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Match ended')),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Unmatch'),
              ),
            ],
          ),
    );
  }

  void _showBlockConfirmation(
    BuildContext context,
    WidgetRef ref,
    String matchId,
    String displayName,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Block $displayName?'),
            content: const Text(
              'Blocking removes visibility, ends the match, and prevents future pairing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await ref.read(blockDatingMatchProvider(matchId).future);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User blocked')),
                    );
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Block'),
              ),
            ],
          ),
    );
  }

  void _showReportDialog(
    BuildContext context,
    WidgetRef ref,
    String matchId,
    String displayName,
  ) {
    const categories = <String>[
      'safety_concern',
      'harassment',
      'impersonation',
      'romance_scam',
      'underage_risk',
      'sexual_content',
      'spam',
      'other',
    ];
    final detailsController = TextEditingController();
    String selectedCategory = categories.first;

    showDialog<void>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Text('Report $displayName'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        items:
                            categories
                                .map(
                                  (category) => DropdownMenuItem<String>(
                                    value: category,
                                    child: Text(category.replaceAll('_', ' ')),
                                  ),
                                )
                                .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => selectedCategory = value);
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Reason',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      Gap(Spacing.md.h),
                      TextField(
                        controller: detailsController,
                        maxLines: 4,
                        maxLength: 500,
                        decoration: const InputDecoration(
                          labelText: 'Details (optional)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await ref.read(
                          reportDatingMatchProvider((
                            matchId: matchId,
                            category: selectedCategory,
                            details:
                                detailsController.text.trim().isEmpty
                                    ? null
                                    : detailsController.text.trim(),
                          )).future,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Thank you for reporting. We will review it.',
                              ),
                            ),
                          );
                        }
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
          ),
    ).whenComplete(detailsController.dispose);
  }
}
