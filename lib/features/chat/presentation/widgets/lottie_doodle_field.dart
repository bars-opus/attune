import 'package:attune/features/chat/presentation/widgets/doodle_packing.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// The Lottie motifs available to the wallpaper.
///
/// The heaviest assets are deliberately excluded. statistics.json is
/// 705KB with 20 nested assets — a single copy costs more than every
/// other motif combined, and a packed field renders dozens.
const List<String> kLottieDoodleAssets = [
  'assets/lottie/message.json',
  'assets/lottie/profile.json',
  'assets/lottie/images.json',
  'assets/lottie/shops.json',
  'assets/lottie/reccuring.json',
  'assets/lottie/dashboard.json',
];

/// Ceiling on simultaneous Lottie widgets.
///
/// Each one owns a parsed composition and its own controller, where the
/// SVG field shares a single ticker across the whole wallpaper. 40 is
/// about where a packed look survives without putting dozens of
/// independent animators behind a conversation.
const int kMaxLottieDoodles = 40;

/// A packed doodle wallpaper built from Lottie motifs.
///
/// Uses the same packing as the SVG field, so the arrangement matches —
/// only the artwork differs. See DoodleField for the lighter variant.
class LottieDoodleField extends StatelessWidget {
  const LottieDoodleField({
    super.key,
    required this.color,
    this.seed = 7,
    this.opacity = 0.08,
  });

  final Color color;
  final int seed;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final all = packDoodles(
          area: area,
          assetCount: kLottieDoodleAssets.length,
          seed: seed,
        );

        // Thin the packed field rather than loosening the packing: keeping
        // an even stride preserves the spread, where taking the first N
        // would fill the top and leave the bottom bare.
        //
        // The stride is computed to land AT the cap rather than by
        // dividing and rounding up — ceil() overshoots badly on a field
        // only slightly larger than the cap, thinning 48 down to 24.
        final placements = all.length <= kMaxLottieDoodles
            ? all
            : [
                for (var i = 0; i < kMaxLottieDoodles; i++)
                  all[(i * all.length ~/ kMaxLottieDoodles)],
              ];

        return Opacity(
          opacity: opacity,
          child: Stack(
            children: [
              for (final placement in placements)
                Positioned.fromRect(
                  rect: placement.rect,
                  child: IgnorePointer(
                    child: RotatedBox(
                      quarterTurns: placement.turns,
                      child: Lottie.asset(
                        kLottieDoodleAssets[placement.assetIndex],
                        fit: BoxFit.contain,
                        // Only a minority animate, and reduce-motion stops
                        // all of them — the motif still renders, frozen.
                        animate: placement.isAnimated && !reduceMotion,
                        repeat: placement.isAnimated && !reduceMotion,
                        delegates: LottieDelegates(
                          values: [
                            ValueDelegate.colorFilter(
                              const ['**'],
                              value: ColorFilter.mode(color, BlendMode.srcIn),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
