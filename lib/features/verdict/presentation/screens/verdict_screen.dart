import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/verdict/data/models/services/verdict_service.dart';
import 'package:attune/features/verdict/data/models/verdict.dart';
import 'package:attune/features/verdict/presentation/providers/verdict_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class VerdictScreen extends ConsumerStatefulWidget {
  const VerdictScreen({super.key});

  @override
  ConsumerState<VerdictScreen> createState() => _VerdictScreenState();
}

class _VerdictScreenState extends ConsumerState<VerdictScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  bool _showHeadline = false;
  bool _showFull = false;
  String? _viewedVerdictId;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: const Duration(milliseconds: 450),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  void _startRevealSequence({required bool disableAnimations}) {
    if (_showHeadline && _showFull) {
      return;
    }

    if (disableAnimations) {
      setState(() {
        _showHeadline = true;
        _showFull = true;
      });
      _revealController.value = 1;
      return;
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() => _showHeadline = true);
      }
    });

    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() => _showFull = true);
        _revealController.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final verdictAsync = ref.watch(verdictLoadProvider);
    final disableAnimations =
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your monthly summary'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: verdictAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildUnavailableState(context),
        data: (state) {
          if (state.verdict != null) {
            _startRevealSequence(disableAnimations: disableAnimations);
            _markViewedIfNeeded(state.verdict!);
            return _buildVerdict(context, state, disableAnimations);
          }

          return switch (state.status) {
            VerdictLoadStatus.ineligible => _buildEmptyState(
              context,
              message:
                  state.message ??
                  'Keep using Attune at your own pace and this summary will become available when there is enough to ground it.',
            ),
            VerdictLoadStatus.queued || VerdictLoadStatus.processing =>
              _buildQueuedState(context, state.message),
            _ => _buildUnavailableState(context),
          };
        },
      ),
    );
  }

  void _markViewedIfNeeded(Verdict verdict) {
    if (_viewedVerdictId == verdict.id) {
      return;
    }
    _viewedVerdictId = verdict.id;
    Future.microtask(() async {
      final service = ref.read(verdictServiceProvider);
      await service.markViewed(verdict.id);
    });
  }

  Widget _buildVerdict(
    BuildContext context,
    VerdictLoadState state,
    bool disableAnimations,
  ) {
    final verdict = state.verdict!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final periodLabel = _formatPeriod(state.periodStart);

    if (disableAnimations) {
      _showHeadline = true;
      _showFull = true;
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(Spacing.lg.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: textTheme.labelLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          Gap(Spacing.sm.h),
          _buildConfidenceChip(context, verdict.confidenceLabel),
          Gap(Spacing.md.h),
          if (_showHeadline)
            Text(
              verdict.headline,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          if (_showFull) ...[
            Gap(Spacing.xl.h),
            _buildSectionTitle(context, 'Strengths'),
            Gap(Spacing.md.h),
            ...verdict.strengths.map(
              (item) => _buildItemCard(
                item,
                colorScheme: colorScheme,
                textTheme: textTheme,
                accent: colorScheme.primary,
                background: colorScheme.primary.withValues(alpha: 0.05),
              ),
            ),
            Gap(Spacing.xl.h),
            _buildSectionTitle(context, 'Watch areas'),
            Gap(Spacing.md.h),
            ...verdict.watchAreas.map(
              (item) => _buildItemCard(
                item,
                colorScheme: colorScheme,
                textTheme: textTheme,
                accent: colorScheme.secondary,
                background: colorScheme.secondary.withValues(alpha: 0.08),
              ),
            ),
            if (verdict.oneAction.trim().isNotEmpty) ...[
              Gap(Spacing.xl.h),
              _buildSectionTitle(context, 'One conversation starter'),
              Gap(Spacing.md.h),
              Container(
                padding: EdgeInsets.all(Spacing.md.w),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.35,
                  ),
                  borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                ),
                child: Text(verdict.oneAction, style: textTheme.bodyMedium),
              ),
            ],
            Gap(Spacing.xl.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(Spacing.md.w),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
              ),
              child: Text(
                verdict.disclaimer,
                style: textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Dismiss',
              onPressed: () async {
                await ref
                    .read(verdictServiceProvider)
                    .markDismissed(verdict.id);
                if (!context.mounted) {
                  return;
                }
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              size: ButtonSize.medium,
              customColor: colorScheme.surfaceContainerHighest,
              textColor: colorScheme.onSurface,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfidenceChip(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: Spacing.sm.w,
        vertical: Spacing.xs.h,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm.r),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildItemCard(
    VerdictItem item, {
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required Color accent,
    required Color background,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: Spacing.md.h),
      padding: EdgeInsets.all(Spacing.md.w),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          Gap(Spacing.xs.h),
          Text(item.body, style: textTheme.bodyMedium),
          if ((item.source ?? '').trim().isNotEmpty) ...[
            Gap(Spacing.sm.h),
            Text(
              item.source!,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required String message}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart_outlined,
              size: 64,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            Gap(Spacing.md.h),
            Text(
              'Not enough shared data yet',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              message,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Start a check-in',
              onPressed: () => Navigator.pop(context),
              size: ButtonSize.medium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueuedState(BuildContext context, String? message) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            Gap(Spacing.lg.h),
            Text(
              'Your summary is being prepared',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              message ??
                  'Check back shortly to see the patterns reflected in your shared data.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnavailableState(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(Spacing.xl.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Your summary is unavailable right now.',
              style: textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.sm.h),
            Text(
              'Try again later.',
              style: textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatPeriod(DateTime periodStart) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[periodStart.month - 1]} ${periodStart.year}';
  }
}
