import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/utils/exports/export_screens.dart';

/// Placeholder for ChatSettingsScreen's avatar+name identity card, shown
/// while PulseTab's _ChatSettingsTab wrapper is still resolving
/// currentRelationshipIdProvider/getConversation() — the only data on that
/// whole screen genuinely not available yet (see
/// ChatSettingsStaticRows, which renders for real immediately since none
/// of it needs Conversation to draw its icons/titles/subtitles). Mirrors
/// the identity card's real layout (circular avatar, "Change photo" label,
/// a field-shaped bar) so the page doesn't visually jump once the real
/// card swaps in.
class ChatSettingsIdentitySkeleton extends StatelessWidget {
  const ChatSettingsIdentitySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholderColor = colorScheme.surfaceContainerHighest;

    return CardInkWell(
      child: Column(
        children: [
          Gap(Spacing.xl.h),
          Center(
            child: Shimmer(
              sweeps: null,
              child: CircleAvatar(
                radius: 40.h,
                backgroundColor: placeholderColor,
              ),
            ),
          ),
          Gap(Spacing.sm.h),
          Center(
            child: Shimmer(
              sweeps: null,
              child: Container(
                width: 80.w,
                height: 12.h,
                decoration: BoxDecoration(
                  color: placeholderColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          Gap(Spacing.xl.h),
          Shimmer(
            sweeps: null,
            child: Container(
              width: double.infinity,
              height: 56.h,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Gap(Spacing.xl.h),
        ],
      ),
    );
  }
}
