import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_map/presentation/widgets/glass_surface.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/material.dart';

/// Top left, always visible: who can see you right now (spec §3.1).
class SharingChip extends StatelessWidget {
  const SharingChip({
    super.key,
    required this.label,
    required this.status,
    required this.locationOff,
    required this.onTap,
  });
  final String label;

  /// Null while my state hasn't been read: a neutral icon, no claim.
  final PresenceStatus? status;
  final bool locationOff;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      null => (Icons.location_searching, cs.onSurfaceVariant),
      PresenceStatus.off => (Icons.location_off_outlined, cs.onSurfaceVariant),
      PresenceStatus.paused => (
        Icons.pause_circle_outline,
        cs.onSurfaceVariant,
      ),
      PresenceStatus.sharing when locationOff => (
        Icons.location_disabled,
        cs.error,
      ),
      PresenceStatus.sharing => (Icons.location_on, cs.primary),
    };
    return Semantics(
      button: true,
      label: 'Sharing: $label',
      hint: 'Opens sharing settings',
      onTap: onTap,
      excludeSemantics: true,
      // A 48 dp hit area around a 44 dp chip, like the glass buttons beside
      // it (same visual height).
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: GlassPanel(
                borderRadius: BorderRadiusTokens.floatingNavAll,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadiusTokens.floatingNavAll,
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.smMd,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: cs.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
