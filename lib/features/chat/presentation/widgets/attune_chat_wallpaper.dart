import 'dart:ui';

import 'package:attune/app/theme/chat_color_scheme.dart';
import 'package:flutter/material.dart';

class AttuneChatWallpaper extends StatefulWidget {
  const AttuneChatWallpaper({
    super.key,
    required this.child,
    this.scrollController,
  });

  static const _assetPath =
      'assets/images/attune_chat_wallpaper_tile_refined.png';
  static const _showDarkGradient = true;
  // Restore the background accent independently of the pattern tint/glow.
  static const _showPatternGlow = false;

  final Widget child;
  final ScrollController? scrollController;

  @override
  State<AttuneChatWallpaper> createState() => _AttuneChatWallpaperState();
}

class _AttuneChatWallpaperState extends State<AttuneChatWallpaper> {
  /// Quantised progress (1/64 steps). Rebuilding on every pixel of scroll
  /// repainted the whole screen for changes nobody can see.
  double _progress = 0;
  static const _steps = 64;

  /// Whether the last build painted [_progress] (the dark gradient). Light
  /// mode never reads it, so scrolling there must not rebuild anything.
  bool _tracksScroll = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScroll);
    _syncProgress();
  }

  @override
  void didUpdateWidget(covariant AttuneChatWallpaper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.removeListener(_onScroll);
      widget.scrollController?.addListener(_onScroll);
      // Attached to a list already scrolled: show its place now, not at
      // its next scroll.
      _syncProgress();
    }
  }

  double _quantisedProgress(ScrollController controller) =>
      (_scrollGradientProgress(controller) * _steps).round() / _steps;

  /// Reads the attached list's current place (no setState: called where a
  /// build follows anyway).
  void _syncProgress() {
    final controller = widget.scrollController;
    _progress =
        controller == null || !controller.hasClients
            ? 0
            : _quantisedProgress(controller);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_tracksScroll) return;
    final controller = widget.scrollController;
    if (controller == null || !controller.hasClients) return;
    final quantised = _quantisedProgress(controller);
    if (quantised == _progress) return;
    setState(() => _progress = quantised);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usesScroll =
        widget.scrollController != null &&
        isDark &&
        AttuneChatWallpaper._showDarkGradient;
    // Switched to dark while scrolled: _progress went stale while light
    // mode ignored the scroll.
    if (usesScroll && !_tracksScroll) _syncProgress();
    _tracksScroll = usesScroll;
    return _buildWallpaper(context, usesScroll ? _progress : 0);
  }

  Widget _buildWallpaper(BuildContext context, double scrollProgress) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark &&
        AttuneChatWallpaper._showDarkGradient;
    final showPatternGlow = isDark && AttuneChatWallpaper._showPatternGlow;
    final chatColors = Theme.of(context).chatColors;
    final topLeftAccentOpacity = scrollProgress;
    final bottomRightAccentOpacity = 1 - scrollProgress;
    final backgroundAccent =
        Color.lerp(chatColors.background, chatColors.backgroundAccent, 0.28)!;
    final patternAccent =
        Color.lerp(chatColors.pattern, chatColors.backgroundAccent, 0.42)!;
    final patternGlow =
        Color.lerp(chatColors.pattern, chatColors.backgroundAccent, 0.72)!;
    final patternGlowOpacity = chatColors.patternOpacity * 1.55;
    const patternGlowBlur = 7.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isDark)
          _WallpaperGradientLayer(
            background: chatColors.background,
            accent: backgroundAccent,
            progress: scrollProgress,
          )
        else
          ExcludeSemantics(child: ColoredBox(color: chatColors.background)),
        if (showPatternGlow)
          ExcludeSemantics(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback:
                      (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
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
                                    patternGlowOpacity *
                                    bottomRightAccentOpacity,
                              ),
                            ],
                            stops: const [0, 0.46, 1],
                          ).createShader(bounds),
                      child: const _WallpaperTile(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showPatternGlow)
          ExcludeSemantics(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback:
                      (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
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
                                alpha:
                                    patternGlowOpacity * topLeftAccentOpacity,
                              ),
                            ],
                            stops: const [0, 0.46, 1],
                          ).createShader(bounds),
                      child: const _WallpaperTile(),
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
                child:
                    showPatternGlow
                        ? ShaderMask(
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
                          child: const _WallpaperTile(),
                        )
                        : ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            chatColors.pattern.withValues(
                              alpha: chatColors.patternOpacity,
                            ),
                            BlendMode.srcIn,
                          ),
                          child: const _WallpaperTile(),
                        ),
              ),
            ),
          ),
        ),
        if (showPatternGlow)
          ExcludeSemantics(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback:
                      (bounds) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
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
                      child: const _WallpaperTile(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        widget.child,
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

/// The two former layers (a fixed topLeft->bottomRight gradient under a
/// bottomRight->topLeft one faded in by scroll) composited exactly into a
/// single gradient: no Opacity, no saveLayer. Both ran on stops [0, 0.5, 1],
/// so their alpha blend is piecewise-linear on the same stops:
/// t=0 -> lerp(bg, accent, p); t=0.5 -> the shared mid colour;
/// t=1 -> lerp(accent, bg, p).
class _WallpaperGradientLayer extends StatelessWidget {
  const _WallpaperGradientLayer({
    required this.background,
    required this.accent,
    required this.progress,
  });

  final Color background;
  final Color accent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final mid = Color.lerp(background, accent, 0.2)!;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(background, accent, progress)!,
                mid,
                Color.lerp(accent, background, progress)!,
              ],
              stops: const [0, 0.5, 1],
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => DecoratedBox(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage(AttuneChatWallpaper._assetPath),
            // The 1024px artwork occupies 85% of the chat width. Scaling the
            // whole composition tightens gaps along with the existing shapes.
            scale: 1024 / (constraints.maxWidth * 0.85),
            repeat: ImageRepeat.repeat,
            alignment: Alignment.topCenter,
            fit: BoxFit.none,
            filterQuality: FilterQuality.high,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
