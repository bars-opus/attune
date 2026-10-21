import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart'
    show kComposerShadows;
import 'package:flutter/material.dart';

/// The pill's screen-reader label — one plural-ready function, so it maps
/// 1:1 onto an ICU message when chat strings are extracted.
String scrollToLatestSemanticsLabel(int count) =>
    count > 0 ? 'Jump to newest, $count new' : 'Jump to newest message';

/// WhatsApp's "↓" button: shown once the reader has scrolled away from the
/// newest message, with a badge counting partner messages that arrived
/// since. Sits on the same surface and shadow as the composer.
class ScrollToLatestPill extends StatelessWidget {
  const ScrollToLatestPill({
    super.key,
    required this.visible,
    required this.count,
    required this.onTap,
  });

  final bool visible;
  final int count;
  final VoidCallback onTap;

  /// Material's minimum target (above iOS's 44) — the margin around the
  /// circle taps too, so a near miss does not scroll the list underneath.
  static const double _hitSize = 48;
  static const double _circleSize = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final instant = reduceMotionOf(context);
    final duration =
        instant ? Duration.zero : const Duration(milliseconds: 180);
    // Hidden, it takes no pointer and is not announced.
    return ExcludeSemantics(
      excluding: !visible,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          child: AnimatedSlide(
            offset: visible ? Offset.zero : const Offset(0, 0.4),
            duration: duration,
            curve: Curves.easeOutCubic,
            child: Semantics(
              button: true,
              label: scrollToLatestSemanticsLabel(count),
              excludeSemantics: true,
              onTap: onTap,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: SizedBox.square(
                  dimension: _hitSize,
                  child: Center(child: _circle(theme)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circle(ThemeData theme) {
    final badge = count > 99 ? '99+' : '$count';
    return Material(
      color: theme.chatControlSurface,
      shape: const CircleBorder(),
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: const ShapeDecoration(
          shape: CircleBorder(),
          shadows: kComposerShadows,
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: _circleSize,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: theme.colorScheme.onSurface,
                ),
                if (count > 0)
                  PositionedDirectional(
                    top: -6,
                    end: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
