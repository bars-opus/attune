import 'dart:ui';

import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';

class AttuneChatWallpaper extends StatelessWidget {
  const AttuneChatWallpaper({
    super.key,
    required this.child,
    this.scrollController,
  });

  static const _assetPath = 'assets/images/attune_chat_wallpaper_tile.png';

  final Widget child;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final controller = scrollController;
    if (controller == null) return _buildWallpaper(context, 0);

    return AnimatedBuilder(
      animation: controller,
      builder:
          (context, child) =>
              _buildWallpaper(context, _scrollGradientProgress(controller)),
    );
  }

  Widget _buildWallpaper(BuildContext context, double scrollProgress) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatColors = Theme.of(context).chatColors;
    final topLeftAccentOpacity = scrollProgress;
    final bottomRightAccentOpacity = 1 - scrollProgress;
    final backgroundAccent =
        isDark
            ? Color.lerp(
              chatColors.background,
              chatColors.backgroundAccent,
              0.42,
            )!
            : Color.lerp(
              chatColors.background,
              chatColors.backgroundAccent,
              0.60,
            )!;
    final patternAccent =
        Color.lerp(chatColors.pattern, chatColors.backgroundAccent, 0.42)!;
    final patternGlow =
        Color.lerp(chatColors.pattern, chatColors.backgroundAccent, 0.72)!;
    final patternGlowOpacity =
        isDark
            ? chatColors.patternOpacity * 1.55
            : chatColors.patternOpacity * 0.36;
    final patternGlowBlur = isDark ? 7.0 : 5.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        _WallpaperGradientLayer(
          background: chatColors.background,
          accent: backgroundAccent,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          opacity: 1,
        ),
        _WallpaperGradientLayer(
          background: chatColors.background,
          accent: backgroundAccent,
          begin: Alignment.bottomRight,
          end: Alignment.topLeft,
          opacity: topLeftAccentOpacity,
        ),
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
                      stops: [0, 0.82, 1],
                    ).createShader(bounds),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: patternGlowBlur,
                    sigmaY: patternGlowBlur,
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback:
                        (bounds) => LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.transparent,
                            patternGlow.withValues(
                              alpha: 0.02 * bottomRightAccentOpacity,
                            ),
                            patternGlow.withValues(
                              alpha:
                                  patternGlowOpacity * bottomRightAccentOpacity,
                            ),
                          ],
                          stops: const [0, 0.46, 1],
                        ).createShader(bounds),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(_assetPath),
                          repeat: ImageRepeat.repeat,
                          alignment: Alignment.topLeft,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
                      stops: [0, 0.82, 1],
                    ).createShader(bounds),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: patternGlowBlur,
                    sigmaY: patternGlowBlur,
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback:
                        (bounds) => LinearGradient(
                          begin: Alignment.bottomRight,
                          end: Alignment.topLeft,
                          colors: [
                            Colors.transparent,
                            patternGlow.withValues(
                              alpha: 0.02 * topLeftAccentOpacity,
                            ),
                            patternGlow.withValues(
                              alpha: patternGlowOpacity * topLeftAccentOpacity,
                            ),
                          ],
                          stops: const [0, 0.46, 1],
                        ).createShader(bounds),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(_assetPath),
                          repeat: ImageRepeat.repeat,
                          alignment: Alignment.topLeft,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
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
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback:
                      (bounds) => LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          chatColors.pattern.withValues(
                            alpha: chatColors.patternOpacity,
                          ),
                          chatColors.pattern.withValues(
                            alpha: chatColors.patternOpacity,
                          ),
                          patternAccent.withValues(
                            alpha: chatColors.patternOpacity,
                          ),
                        ],
                        stops: const [0, 0.44, 1],
                      ).createShader(bounds),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(_assetPath),
                        repeat: ImageRepeat.repeat,
                        alignment: Alignment.topLeft,
                        filterQuality: FilterQuality.low,
                      ),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
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
                child: Opacity(
                  opacity: topLeftAccentOpacity,
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback:
                        (bounds) => LinearGradient(
                          begin: Alignment.bottomRight,
                          end: Alignment.topLeft,
                          colors: [
                            chatColors.pattern.withValues(
                              alpha: chatColors.patternOpacity,
                            ),
                            chatColors.pattern.withValues(
                              alpha: chatColors.patternOpacity,
                            ),
                            patternAccent.withValues(
                              alpha: chatColors.patternOpacity,
                            ),
                          ],
                          stops: const [0, 0.44, 1],
                        ).createShader(bounds),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage(_assetPath),
                          repeat: ImageRepeat.repeat,
                          alignment: Alignment.topLeft,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  double _scrollGradientProgress(ScrollController controller) {
    if (!controller.hasClients) return 0;

    // This is an ambient response to the user's first scroll, not a map of
    // the full message history. Keeping the travel range fixed lets the
    // gradient start moving immediately even in very long conversations.
    const range = 620.0;
    final raw = (controller.offset / range).clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(raw);
  }
}

class _WallpaperGradientLayer extends StatelessWidget {
  const _WallpaperGradientLayer({
    required this.background,
    required this.accent,
    required this.begin,
    required this.end,
    required this.opacity,
  });

  final Color background;
  final Color accent;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [background, background, accent],
              stops: const [0, 0.34, 1],
            ),
          ),
        ),
      ),
    );
  }
}
