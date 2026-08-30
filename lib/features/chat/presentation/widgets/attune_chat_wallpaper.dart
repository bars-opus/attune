import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';

class AttuneChatWallpaper extends StatelessWidget {
  const AttuneChatWallpaper({super.key, required this.child});

  static const _assetPath = 'assets/images/attune_chat_wallpaper_tile.png';

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chatColors = Theme.of(context).chatColors;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(child: ColoredBox(color: chatColors.background)),
        ExcludeSemantics(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback:
                    (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, 0.78, 1],
                    ).createShader(bounds),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: const AssetImage(_assetPath),
                      repeat: ImageRepeat.repeat,
                      alignment: Alignment.topLeft,
                      filterQuality: FilterQuality.low,
                      colorFilter: ColorFilter.mode(
                        chatColors.pattern.withValues(
                          alpha: chatColors.patternOpacity,
                        ),
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
