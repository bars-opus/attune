import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/domain/couple_map_copy.dart';
import 'package:attune/features/couple_map/presentation/providers/couple_map_providers.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({this.url, required this.initials});
  final String? url;
  final String initials;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = url;
    return CircleAvatar(
      radius: 16,
      backgroundColor: cs.surface,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: cs.primaryContainer,
        foregroundImage:
            u == null || u.isEmpty ? null : CachedNetworkImageProvider(u),
        // Initials stay visible; a broken URL isn't an error worth reporting.
        onForegroundImageError: u == null || u.isEmpty ? null : (_, __) {},
        child: Text(
          initials,
          style: TextStyle(fontSize: 11, color: cs.onPrimaryContainer),
        ),
      ),
    );
  }
}

/// Bottom of the map: both avatars and how far apart, in words (§3.1).
class DistanceCard extends StatelessWidget {
  const DistanceCard({super.key, required this.copy, required this.people});
  final DistanceCardCopy copy;
  final CoupleMapPeople people;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      container: true,
      label:
          copy.details.isEmpty
              ? copy.headline
              : '${copy.headline}. ${copy.details}',
      excludeSemantics: true,
      child: GlassPanel(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              height: 32,
              child: Stack(
                children: [
                  _MiniAvatar(
                    url: people.selfUrl,
                    initials: people.selfInitials,
                  ),
                  Positioned(
                    left: 20,
                    child: _MiniAvatar(
                      url: people.partnerUrl,
                      initials: people.partnerInitials,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: copy.together ? cs.primary : cs.onSurface,
                    ),
                  ),
                  if (copy.details.isNotEmpty)
                    Text(
                      copy.details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one line shown instead of the card (spec §3.4). Tappable only when
/// it leads somewhere I can act: my own sharing or my own location.
class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.notice, this.onTap});
  final CoupleMapNotice notice;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Row(
        children: [
          Icon(
            notice == CoupleMapNotice.justYou
                ? Icons.person_pin_circle_outlined
                : Icons.near_me_outlined,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(noticeText(notice), style: theme.textTheme.bodyMedium),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
    return GlassPanel(
      child:
          onTap == null
              ? body
              : Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadiusTokens.lgAll,
                  onTap: onTap,
                  child: body,
                ),
              ),
    );
  }
}

/// A failed first read with nothing to show (checklist 1.3): plain copy,
/// tap to retry.
class RetryCard extends StatelessWidget {
  const RetryCard({super.key, required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassPanel(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadiusTokens.lgAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(Icons.refresh, color: cs.onSurfaceVariant),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Text(
                    "Couldn't load your map. Try again.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown within the first frame while presence loads (checklist 5.2).
class LoadingCard extends StatelessWidget {
  const LoadingCard({super.key});
  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: const EdgeInsets.all(Spacing.md),
    child: Row(
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: Spacing.md),
        Text(
          'Loading your map…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
