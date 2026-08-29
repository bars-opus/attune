import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AttuneChatWallpaper extends StatelessWidget {
  const AttuneChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chatColors = Theme.of(context).chatColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: ColoredBox(color: chatColors.background)),
        const _LottieExperimentLayer(),
        child,
      ],
    );
  }
}

/// Experimental Lottie-only wallpaper layer.
class _LottieExperimentLayer extends StatelessWidget {
  const _LottieExperimentLayer();

  static const _assetRoot = 'assets/lottie';
  static const _assetNames = [
    'message.json',
    'profile.json',
    'images.json',
    'shops.json',
    'reccuring.json',
  ];
  static const _motifSize = 66.0;

  @override
  Widget build(BuildContext context) {
    final chatColors = Theme.of(context).chatColors;
    final reduceMotion = reduceMotionOf(context);
    final baseOpacity = (chatColors.patternOpacity * 1.45).clamp(0, 1);

    return Positioned.fill(
      key: const ValueKey('chat-wallpaper-lottie-experiment'),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: _WallpaperFade(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final height = constraints.maxHeight;
                  final motifs = _buildMotifs(width, height);

                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children:
                        motifs.map((motif) {
                          return _LottieWallpaperMotif(
                            key: ValueKey('chat-lottie-${motif.index}'),
                            assetPath: '$_assetRoot/${motif.assetName}',
                            color: chatColors.pattern.withValues(
                              alpha: (baseOpacity * motif.opacityBoost).clamp(
                                0,
                                1,
                              ),
                            ),
                            animate: !reduceMotion && motif.animate,
                            left: motif.left,
                            top: motif.top,
                            size: motif.size,
                            angle: motif.angle,
                          );
                        }).toList(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_LottieWallpaperData> _buildMotifs(double width, double height) {
    const horizontalStep = 56.0;
    const verticalStep = 50.0;
    final columns = (width / horizontalStep).ceil() + 2;
    final rows = (height / verticalStep).ceil() + 2;
    final motifs = <_LottieWallpaperData>[];

    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final index = motifs.length;
        final stagger = row.isOdd ? horizontalStep / 2 : 0.0;
        final diagonalLift = column * 3.0;
        final left = column * horizontalStep + stagger - horizontalStep;
        final top = row * verticalStep - verticalStep - diagonalLift;

        motifs.add(
          _LottieWallpaperData(
            index: index,
            assetName: _assetNames[(row * 2 + column) % _assetNames.length],
            left: left,
            top: top,
            size: _motifSize,
            angle: _angleFor(row, column),
            opacityBoost: _opacityBoostFor(row, column),
            animate: _shouldAnimate(row, column),
          ),
        );
      }
    }

    return motifs;
  }

  double _angleFor(int row, int column) {
    const angles = [-0.24, 0.18, -0.1, 0.26, -0.18, 0.12];
    return angles[(row + column * 2) % angles.length];
  }

  double _opacityBoostFor(int row, int column) {
    const boosts = [1.0, 1.1, 1.04, 1.16, 1.08];
    return boosts[(row * 3 + column) % boosts.length];
  }

  bool _shouldAnimate(int row, int column) {
    return (row * 17 + column * 31) % 8 == 0;
  }
}

class _LottieWallpaperMotif extends StatelessWidget {
  const _LottieWallpaperMotif({
    super.key,
    required this.assetPath,
    required this.color,
    required this.animate,
    required this.top,
    required this.size,
    required this.angle,
    required this.left,
  });

  final String assetPath;
  final Color color;
  final bool animate;
  final double left;
  final double top;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: Transform.rotate(
        angle: angle,
        child: Padding(
          padding: EdgeInsets.all(size * 0.08),
          child: ColorFiltered(
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            child: Lottie.asset(
              assetPath,
              key: ValueKey('$assetPath-animation'),
              animate: animate,
              repeat: animate,
              fit: BoxFit.contain,
              frameRate: FrameRate.composition,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

class _LottieWallpaperData {
  const _LottieWallpaperData({
    required this.index,
    required this.assetName,
    required this.left,
    required this.top,
    required this.size,
    required this.angle,
    required this.opacityBoost,
    required this.animate,
  });

  final int index;
  final String assetName;
  final double left;
  final double top;
  final double size;
  final double angle;
  final double opacityBoost;
  final bool animate;
}

class _WallpaperFade extends StatelessWidget {
  const _WallpaperFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback:
          (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.78, 1],
          ).createShader(bounds),
      child: child,
    );
  }
}
