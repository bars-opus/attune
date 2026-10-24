import 'dart:io';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The take, full bleed, with Retake and Share (owner ruling 1, overriding
/// spec §6.1's "the outbox is the review"). A fixed black media surface in
/// both themes: literal white foreground, as the camera itself uses.
class StoryReviewLayer extends StatelessWidget {
  const StoryReviewLayer({
    super.key,
    required this.media,
    required this.videoController,
    required this.posting,
    required this.onShare,
    required this.onRetake,
    required this.onClose,
  });

  final CapturedMedia media;
  final VideoPlayerController? videoController;

  /// Share was tapped and the take is being prepared: both buttons are
  /// inert and Close is hidden (the embedder also blocks back).
  final bool posting;
  final VoidCallback onShare;
  final VoidCallback onRetake;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final video = videoController;
    final isPhoto = media.type == CapturedMediaType.image;
    final Widget preview =
        isPhoto
            ? Image.file(
              File(media.path),
              key: const ValueKey('story-review-image'),
              fit: BoxFit.cover,
              semanticLabel: 'Your photo, not shared yet',
              // A take that cannot be shown (unreadable, or already
              // cleaned up as the review closes) must not throw or block
              // Share.
              errorBuilder:
                  (context, error, stack) => const Center(
                    child: Icon(
                      Icons.photo_rounded,
                      size: IconSizes.xl,
                      color: Colors.white70,
                    ),
                  ),
            )
            : video != null && video.value.isInitialized
            ? Semantics(
              label: 'Your video, not shared yet',
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: video.value.size.width,
                  height: video.value.size.height,
                  child: VideoPlayer(video),
                ),
              ),
            )
            : const Center(
              // A preview that will not open must not block Share.
              child: Icon(
                Icons.videocam_rounded,
                size: IconSizes.xl,
                color: Colors.white70,
                semanticLabel: 'Your video, not shared yet',
              ),
            );

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(child: preview),
          if (!posting)
            Positioned(
              top: Spacing.xxl,
              left: Spacing.md,
              child: IconButton(
                key: const ValueKey('story-review-close'),
                iconSize: IconSizes.lg,
                tooltip: 'Discard',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          // The scrim wraps the controls, so it grows with them at large
          // text. A fixed media overlay (not a themed surface), so
          // alpha-black literals, as the camera uses.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.xxl * 2,
                    Spacing.lg,
                    Spacing.xxl,
                  ),
                  child: LayoutBuilder(
                    builder:
                        (context, constraints) =>
                            _controls(context, constraints.maxWidth),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Retake and Share side by side, or stacked full width (Share on top)
  /// when the longest label would not fit on one line in half the width:
  /// small phones at large text. Stacked and still too long, the icons go
  /// (batch-7 review M1). Decided on the longest label either
  /// button can show, so tapping Share never changes the layout.
  Widget _controls(BuildContext context, double maxWidth) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double labelWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: scaler,
        textDirection: direction,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // An icon button's padding (16 + 24), icon and gap, plus slack.
    const chrome = 16 + 24 + IconSizes.md + Spacing.sm + Spacing.sm;
    final longest = [
      'Retake',
      'Share',
      'Sharing…',
    ].map(labelWidth).reduce((a, b) => a > b ? a : b);
    final sideBySide = (longest + chrome) * 2 + Spacing.md <= maxWidth;
    // Stacked and still too long: the words matter more than the icons.
    final icons = sideBySide || longest + chrome <= maxWidth;

    Widget label(String text) => Text(
      text,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );

    final retakeStyle = OutlinedButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
      side: BorderSide(color: posting ? Colors.white24 : Colors.white70),
      minimumSize: const Size.fromHeight(48),
    );
    const retakeKey = ValueKey('story-review-retake');
    final retake =
        icons
            ? OutlinedButton.icon(
              key: retakeKey,
              onPressed: posting ? null : onRetake,
              style: retakeStyle,
              icon: const Icon(Icons.refresh_rounded, size: IconSizes.md),
              label: label('Retake'),
            )
            : OutlinedButton(
              key: retakeKey,
              onPressed: posting ? null : onRetake,
              style: retakeStyle,
              child: label('Retake'),
            );
    final shareStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      // While sharing the button is inert but must still read clearly on
      // black: the theme's disabled colours are near-invisible there.
      disabledBackgroundColor: scheme.primary,
      disabledForegroundColor: scheme.onPrimary,
    );
    // Announced as it changes, so a screen-reader user hears that the take
    // is on its way (batch-7 review M4).
    final shareLabel = Semantics(
      liveRegion: posting,
      child: label(posting ? 'Sharing…' : 'Share'),
    );
    const shareKey = ValueKey('story-review-share');
    final share =
        icons
            ? FilledButton.icon(
              key: shareKey,
              onPressed: posting ? null : onShare,
              style: shareStyle,
              // The spinner fills the icon's slot, so the button keeps its
              // size.
              icon: SizedBox.square(
                dimension: IconSizes.md,
                child:
                    posting
                        ? Padding(
                          padding: const EdgeInsets.all(Spacing.xs),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                        : const Icon(Icons.send_rounded, size: IconSizes.md),
              ),
              label: shareLabel,
            )
            : FilledButton(
              key: shareKey,
              onPressed: posting ? null : onShare,
              style: shareStyle,
              child: shareLabel,
            );

    if (sideBySide) {
      return Row(
        children: [
          Expanded(child: retake),
          const SizedBox(width: Spacing.md),
          Expanded(child: share),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [share, const SizedBox(height: Spacing.sm), retake],
    );
  }
}
