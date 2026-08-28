import 'dart:math' as math;

import 'package:attune/features/chat/presentation/widgets/doodle_packing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The 14 doodle motifs, dealt across the packed field.
const List<String> kDoodleAssets = [
  'assets/images/chat_doodles/candles.svg',
  'assets/images/chat_doodles/car_body.svg',
  'assets/images/chat_doodles/chat_bubble.svg',
  'assets/images/chat_doodles/couple_body.svg',
  'assets/images/chat_doodles/flame.svg',
  'assets/images/chat_doodles/game_controller.svg',
  'assets/images/chat_doodles/gift.svg',
  'assets/images/chat_doodles/headphones.svg',
  'assets/images/chat_doodles/heart.svg',
  'assets/images/chat_doodles/heart_pair_base.svg',
  'assets/images/chat_doodles/heart_pair_main.svg',
  'assets/images/chat_doodles/love_letter.svg',
  'assets/images/chat_doodles/photo_frame.svg',
  'assets/images/chat_doodles/wheel.svg',
];

/// A densely packed, softly animated doodle wallpaper.
///
/// Motion is deliberately restrained: about a tenth of the doodles move,
/// each on its own phase, with a slow breathing scale rather than
/// anything that travels. A wallpaper that draws the eye is a wallpaper
/// competing with the conversation on top of it.
///
/// Under `MediaQuery.disableAnimations` every doodle renders at rest —
/// the field stays complete, only the motion stops.
class DoodleField extends StatefulWidget {
  const DoodleField({
    super.key,
    required this.color,
    this.seed = 7,
    this.opacity = 0.08,
  });

  final Color color;
  final int seed;
  final double opacity;

  @override
  State<DoodleField> createState() => _DoodleFieldState();
}

class _DoodleFieldState extends State<DoodleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    // One slow cycle shared by every animated doodle, each entering it at
    // its own phase. A single controller rather than one per doodle: 17
    // tickers on a chat background is a battery cost with no visible
    // benefit.
    duration: const Duration(seconds: 6),
    vsync: this,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final placements = packDoodles(
          area: area,
          assetCount: kDoodleAssets.length,
          seed: widget.seed,
        );

        return Opacity(
          opacity: widget.opacity,
          child: Stack(
            children: [
              for (final placement in placements)
                Positioned.fromRect(
                  rect: placement.rect,
                  child: _Doodle(
                    placement: placement,
                    color: widget.color,
                    controller: _controller,
                    reduceMotion: reduceMotion,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Doodle extends StatelessWidget {
  const _Doodle({
    required this.placement,
    required this.color,
    required this.controller,
    required this.reduceMotion,
  });

  final DoodlePlacement placement;
  final Color color;
  final AnimationController controller;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final art = RotatedBox(
      quarterTurns: placement.turns,
      child: SvgPicture.asset(
        kDoodleAssets[placement.assetIndex],
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        fit: BoxFit.contain,
      ),
    );

    if (!placement.isAnimated || reduceMotion) return art;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Each doodle enters the shared cycle at its own phase, so the
        // field never beats in unison — synchronised motion reads as a
        // rendering glitch rather than as life.
        final t = (controller.value + placement.phase) % 1.0;
        final breath = math.sin(t * 2 * math.pi);
        return Transform.scale(scale: 1 + breath * 0.06, child: child);
      },
      child: art,
    );
  }
}
