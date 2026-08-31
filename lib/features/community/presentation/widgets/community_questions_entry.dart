import 'package:attune/core/utils/exports/export_screens.dart';

/// "See what other couples are asking" — placed before a game starts.
///
/// This lived only in the games hub, which is being removed. It belongs
/// with the games that actually draw from question pools: seeing what
/// others ask is useful while choosing a tone, and meaningless on a hub
/// that lists games generically.
///
/// [typeFilter] narrows the feed to one game's questions. A game linking
/// here means "questions for THIS game", so landing on everything and
/// making the user find the filter answers a question they did not ask.
class CommunityQuestionsEntry extends StatelessWidget {
  const CommunityQuestionsEntry({
    super.key,
    this.typeFilter,
    this.subtitle = 'See what other couples are asking',
  });

  /// Matches the feed's own filter labels ('This or That', 'Truth',
  /// 'Dare'). Null browses everything.
  final String? typeFilter;

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap:
          () => context.pushNamed(
            'communityFeed',
            queryParameters: {if (typeFilter != null) 'type': typeFilter!},
          ),
      child: Container(
        padding: EdgeInsets.all(Spacing.md.w),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.1),
              colorScheme.primary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.public, size: 28, color: colorScheme.primary),
            Gap(Spacing.md.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Community questions',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(subtitle, style: textTheme.bodySmall),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
