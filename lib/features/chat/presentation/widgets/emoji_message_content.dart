import 'package:animated_emoji/animated_emoji.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

String _normalize(String text) => text.replaceAll('\uFE0F', '');

final _knownEmoji = {
  for (final category in defaultEmojiSet)
    for (final emoji in category.emoji) _normalize(emoji.emoji),
};

/// Uses the same emoji vocabulary as the picker, with grapheme boundaries for
/// families, flags, keycaps and skin tones. Plain digits/text cannot qualify.
List<String> emojiMessageGlyphs(Message message) {
  if (message.isDeleted ||
      message.mediaType != null ||
      message.isSystemNotice ||
      message.isAttuneAssistOutput) {
    return const [];
  }
  return emojiOnlyGlyphs(message.content);
}

/// Also used by the outgoing flight before a Message row exists.
List<String> emojiOnlyGlyphs(String content) {
  final glyphs =
      content
          .trim()
          .characters
          .where((glyph) => glyph.trim().isNotEmpty)
          .toList();
  if (glyphs.isEmpty) return const [];
  for (final glyph in glyphs) {
    final base = String.fromCharCodes(
      glyph.runes.where((rune) => rune < 0x1F3FB || rune > 0x1F3FF),
    );
    if (!_knownEmoji.contains(_normalize(base))) return const [];
  }
  return glyphs;
}

// Only these files are bundled. Unlisted emoji (including skin-tone variants)
// retain their exact native glyph, never substituted with a different tone.
const bundledMessageEmojis = [
  AnimatedEmojis.sleep,
  AnimatedEmojis.sleepy,
  AnimatedEmojis.rollingEyes,
  AnimatedEmojis.relieved,
  AnimatedEmojis.redHeart,
  AnimatedEmojis.twoHearts,
  AnimatedEmojis.sparklingHeart,
  AnimatedEmojis.heartGrow,
  AnimatedEmojis.joy,
  AnimatedEmojis.rofl,
  AnimatedEmojis.blush,
  AnimatedEmojis.heartFace,
  AnimatedEmojis.heartEyes,
  AnimatedEmojis.kissingHeart,
  AnimatedEmojis.hugFace,
  AnimatedEmojis.cry,
  AnimatedEmojis.loudlyCrying,
  AnimatedEmojis.partyPopper,
  AnimatedEmojis.fire,
  AnimatedEmojis.thumbsUp,
  AnimatedEmojis.clap,
];
final _animatedByGlyph = {
  for (final emoji in bundledMessageEmojis)
    _normalize(emoji.toUnicodeEmoji()): emoji,
};

class EmojiMessageContent extends StatefulWidget {
  const EmojiMessageContent({
    super.key,
    required this.glyphs,
    required this.animate,
    this.replayOnVisibility = true,
    this.playbackEnabled = true,
  });
  final List<String> glyphs;
  final bool animate;
  final bool replayOnVisibility;
  final bool playbackEnabled;

  @override
  State<EmojiMessageContent> createState() => _EmojiMessageContentState();
}

class _EmojiMessageContentState extends State<EmojiMessageContent>
    with WidgetsBindingObserver {
  final _visibilityKey = UniqueKey();
  bool _visible = false;
  bool _hasBeenOutside = false;
  bool _pendingEntry = false;
  late bool _initialPlayRequested;
  bool _foreground = true;
  int _playToken = 0;

  @override
  void initState() {
    super.initState();
    _initialPlayRequested = widget.animate;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _canPlay =>
      _foreground &&
      widget.playbackEnabled &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      !reduceMotionOf(context);

  void _consumeEntry() {
    if (!_visible || !_pendingEntry || !_canPlay) return;
    _pendingEntry = false;
    _initialPlayRequested = false;
    _playToken++;
  }

  void _visibilityChanged(VisibilityInfo info) {
    if (!mounted) return;
    // Hysteresis keeps small movements at the viewport edge from restarting.
    if (info.visibleFraction <= 0.05) {
      setState(() {
        _visible = false;
        _hasBeenOutside = true;
        _pendingEntry = false;
      });
    } else if (info.visibleFraction >= 0.5 && !_visible) {
      final scrolled =
          (Scrollable.maybeOf(context)?.position.pixels.abs() ?? 0) > 1;
      setState(() {
        _visible = true;
        _pendingEntry =
            _initialPlayRequested ||
            (widget.replayOnVisibility && (_hasBeenOutside || scrolled));
        _consumeEntry();
      });
    }
  }

  @override
  void didUpdateWidget(covariant EmojiMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !oldWidget.animate) {
      _initialPlayRequested = true;
      _pendingEntry = true;
    }
    _consumeEntry();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _consumeEntry();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _consumeEntry();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VisibilityDetectorController.instance.forget(_visibilityKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glyphs = widget.glyphs;
    final size =
        glyphs.length == 1
            ? 68.0
            : glyphs.length <= 3
            ? 52.0
            : 36.0;
    final content = Semantics(
      label: glyphs.join(' '),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var index = 0; index < glyphs.length; index++)
              _EmojiGlyph(
                key: ValueKey('$index:${glyphs[index]}'),
                glyph: glyphs[index],
                size: size,
                useArtwork: glyphs.length <= 3,
                // Bound simultaneous vector animations in a message.
                playToken: _playToken,
                active: _visible && _canPlay && glyphs.length <= 3,
              ),
          ],
        ),
      ),
    );
    if (!widget.replayOnVisibility && !widget.animate) return content;
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: _visibilityChanged,
      child: content,
    );
  }
}

class _EmojiGlyph extends StatefulWidget {
  const _EmojiGlyph({
    super.key,
    required this.glyph,
    required this.size,
    required this.playToken,
    required this.active,
    required this.useArtwork,
  });
  final String glyph;
  final double size;
  final int playToken;
  final bool active;
  final bool useArtwork;
  @override
  State<_EmojiGlyph> createState() => _EmojiGlyphState();
}

class _EmojiGlyphState extends State<_EmojiGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _loaded = false;
  int _playedToken = 0;
  static bool _licenseRegistered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    if (!_licenseRegistered) {
      _licenseRegistered = true;
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(
          ['Noto Animated Emoji'],
          'Noto Animated Emoji by Google\n'
          'https://googlefonts.github.io/noto-emoji-animation/\n'
          'Licensed under Creative Commons Attribution 4.0 International\n'
          'https://creativecommons.org/licenses/by/4.0/\n'
          'Artwork bundled without modifications via animated_emoji.',
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) _controller.stop();
  }

  void _playIfRequested() {
    if (!widget.active || reduceMotionOf(context)) {
      _controller.stop();
      return;
    }
    if (_loaded && widget.playToken > _playedToken) {
      _playedToken = widget.playToken;
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _EmojiGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    _playIfRequested();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emoji =
        widget.useArtwork ? _animatedByGlyph[_normalize(widget.glyph)] : null;
    final fallback = Center(
      child: Text(
        widget.glyph,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: widget.size * 0.88,
          height: 1.15,
          decoration: TextDecoration.none,
        ),
      ),
    );
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child:
          emoji == null
              ? fallback
              : Stack(
                alignment: Alignment.center,
                children: [
                  if (!_loaded) fallback,
                  AnimatedEmoji(
                    emoji,
                    size: widget.size,
                    source: AnimatedEmojiSource.asset,
                    controller: _controller,
                    repeat: false,
                    errorWidget: fallback,
                    onLoaded: (duration) {
                      if (!mounted || _loaded) return;
                      setState(() => _loaded = true);
                      _controller.duration = Duration(
                        milliseconds: duration.inMilliseconds.clamp(1800, 4000),
                      );
                      _playIfRequested();
                    },
                  ),
                ],
              ),
    );
  }
}
