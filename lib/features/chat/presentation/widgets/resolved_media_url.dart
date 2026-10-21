import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Resolves a signed URL for chat media on demand and builds [child] once
/// ready — the fix for the "Unsupported message" flash a cached (locally
/// restored) message showed before ChatController's hydration pass had a
/// chance to re-sign its URL. [signedMediaUrl] is used immediately when
/// already present (the common case once hydration has run); otherwise
/// this fetches one itself via [signedMediaUrlProvider], keyed on
/// [mediaKey] so it reuses SupabaseChatRepository's own signed-URL cache
/// rather than re-requesting on every rebuild. Shared between MessageBubble
/// and ImageViewerScreen — both need the identical resolve-or-fetch
/// behavior for a message's media.
class ResolvedMediaUrl extends ConsumerWidget {
  const ResolvedMediaUrl({
    super.key,
    required this.signedMediaUrl,
    required this.mediaKey,
    required this.builder,
    required this.loading,
    required this.error,
    this.retryOnTap = true,
    this.retryLabel = 'Tap to retry',
  });

  final String? signedMediaUrl;
  final String? mediaKey;
  final Widget Function(BuildContext context, String url) builder;
  final Widget loading;
  final Widget error;

  /// Whether a broken tile (no URL could be signed, none stored) becomes a
  /// tap-to-retry target. Off where [error] is itself a tap target with its
  /// own meaning — the video poster, whose tile still plays the video.
  final bool retryOnTap;

  /// The retry button's screen-reader label — name the media kind (e.g.
  /// "Photo didn't load. Tap to retry"). English until the chat l10n pass.
  final String retryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = mediaKey;

    // The KEY wins over a stored signedMediaUrl. That URL is baked onto
    // the message at row-fetch time and its token lives 10 minutes, so a
    // chat left open — or a row restored from the disk cache — carries one
    // that has already expired. signedMediaUrlProvider goes through
    // SupabaseChatRepository's cache, which re-signs past a 60s safety
    // margin, so this is a memory hit in the common case rather than a
    // round-trip.
    //
    // The stored URL remains the fallback for a row that carries one
    // without a key.
    if (key == null) {
      return signedMediaUrl != null ? builder(context, signedMediaUrl!) : error;
    }

    // Scoped to this tile's own family member, so one tile re-signing (its
    // pre-expiry refresh, a retry) rebuilds only that tile.
    final resolved = ref.watch(signedMediaUrlProvider(key));

    final failure = resolved.error;
    final lastGoodExpired =
        failure is SignedMediaUrlUnavailable && failure.lastGoodExpired;

    if (resolved.hasValue) {
      // A sign has succeeded before. The last good URL wins while the
      // provider re-signs before expiry, and also if that re-sign fails
      // (offline at the 8-minute mark): the media is cached on disk under
      // its stable key, so a tile already showing its picture keeps it.
      // Bounded by the grant — once the provider reports that URL expired,
      // the tile is the retry button. Never the stored URL here: it was
      // baked on at row fetch and is no fresher than the one that expired.
      if (!lastGoodExpired) return builder(context, resolved.requireValue);
      if (resolved.isLoading) return loading;
    } else {
      // First resolution, or a retry in flight after a failure (tap,
      // connectivity back) — loading, so a tap visibly does something.
      if (resolved.isLoading || !resolved.hasError) return loading;
      // No sign has ever succeeded: the stored URL is the only candidate
      // and, for a row fetched moments ago (hydration signs at fetch), a
      // live one — better than a broken tile.
      if (signedMediaUrl != null) return builder(context, signedMediaUrl!);
    }

    // The tile itself is the retry button (chat review #22).
    if (!retryOnTap) return error;
    void retry() => ref.invalidate(signedMediaUrlProvider(key));
    // excludeSemantics: the broken tile's own visual (an icon) says
    // nothing useful to a screen reader; the button's label is the message.
    // It also hides the GestureDetector's own tap action, so the semantic
    // tap is declared here.
    return Semantics(
      button: true,
      label: retryLabel,
      excludeSemantics: true,
      onTap: retry,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: retry,
        // passthrough: the error tile keeps exactly the constraints it had
        // before the retry glyph went over it. The glyph is positioned, so
        // its LayoutBuilder takes no part in intrinsic sizing (the bubble
        // measures with IntrinsicWidth; a Stack asks only its non-positioned
        // children). It is drawn at a fixed, legible size, and left off a
        // tile too small to carry it — that tile is still a retry button.
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            error,
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.biggest.shortestSide;
                  if (side < _minGlyphTileSide) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.all(side >= 120 ? 8 : 4),
                      child: const _RetryGlyph(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Below this short side a broken tile shows no retry glyph.
const double _minGlyphTileSide = 48;

/// The small refresh badge in a broken tile's corner, so tap-to-retry is
/// discoverable rather than a hidden gesture. Theme surface colours, so it
/// reads on light and dark tiles and on the black viewer alike.
class _RetryGlyph extends StatelessWidget {
  const _RetryGlyph();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          Icons.refresh_rounded,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
