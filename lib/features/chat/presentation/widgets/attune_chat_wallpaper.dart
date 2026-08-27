import 'package:flutter/material.dart';

class AttuneChatWallpaper extends StatelessWidget {
  const AttuneChatWallpaper({super.key, required this.child});

  static const _assetPath = 'assets/images/attune_chat_wallpaper_tile.png';
  static const _lightOpacity = 0.12;
  static const _darkOpacity = 0.10;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final opacity = isDark ? _darkOpacity : _lightOpacity;
    final patternColor = isDark ? Colors.white : Colors.black;

    return Stack(
      fit: StackFit.expand,
      children: [
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
                        patternColor.withValues(alpha: opacity),
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
